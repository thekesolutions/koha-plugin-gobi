# Avoiding duplicate items when importing GOBI cataloguing records

GOBI orders arrive in Koha in two separate steps, and it's easy to end up
with two item records for the same physical copy if the second step isn't
configured correctly. This note explains why that happens and the
recommended configuration to avoid it.

## The two-step workflow

1. **Order placement.** GOBI calls this plugin's API with a purchase order.
   `add_order()` creates the basket, a basic biblio (from the minimal MARC
   record embedded in the order message), the Koha order, and — if
   `AcqCreateItem` resolves to `ordering` — an item per unit ordered, with
   status "Ordered" and no barcode yet (see README, "The plugin follows the
   standard Koha acquisitions workflow", step 6).
2. **Cataloguing record.** Separately (often by email, sometimes days or
   weeks later), GOBI sends a fuller MARC record for the same title,
   including 952/item fields with the real barcode. This record has no
   direct link in Koha to the item created in step 1 — it's imported through
   the standard **Tools → Stage MARC records for import** tool.

## Why "Always add items" creates a duplicate

Koha's MARC import processor (`C4::ImportBatch::_batchCommitItems`) only
reuses/updates an existing item when the incoming record's barcode or
itemnumber matches an item that **already has that value**. Since the
"Ordered" item from step 1 has no barcode yet, there's nothing for the
incoming 952 field to match against, so with **"How to process items: Always
add items"** (or "Add items only if matching bib was found") the importer
always falls through to creating a brand-new item. The result: two items for
one physical copy — the original "Ordered" placeholder, plus a new one built
from the emailed record's 952 field.

"Ignore items" is the only "How to process items" option that avoids this,
because it skips item creation entirely for that import.

## Recommended configuration

When staging the GOBI cataloguing-record email as a MARC import:

- **How to process items:** `Ignore items` — the item already exists from
  the order; nothing should be built from this record's 952 data.
- **Record matching rule:** configure one (e.g. on ISBN/020 or OCLC/035,
  similar to the rule the plugin itself supports for order-time biblio
  matching — see "Record Matching Rules" below) so the fuller cataloguing
  record correctly **overlays the bib record** the order already created,
  instead of risking a second biblio for the same title. This is a
  bib-level setting, independent of the item action above.

## Receiving: attach the barcode to the existing item

Don't create a new item at receiving time either. On the receive screen
(Acquisitions → basket → Receive shipment), when items were created at
ordering, Koha lists the existing order item(s) with an **Edit** link per
item. Use that to open the item editor and enter the GOBI barcode onto the
existing "Ordered" item, then tick it to receive. This keeps a single item
record per physical copy for the whole lifecycle: ordered → catalogued →
received.

## Other things worth checking

- The "Not for loan" value configured on the plugin's settings page (used to
  mark items "Ordered") should match what your circulation policies and
  reports expect for on-order stock.
- The record matching rule used for the plugin's own order-time biblio
  matching (see "Record Matching Rules (ISBN / OCLC)" above) and the
  matching rule used on the generic Stage MARC import tool are two
  independent settings — both need to be configured, not just one.
- This plugin passes `create_items => 'ordering'` explicitly for GOBI
  baskets regardless of the global `AcqCreateItem` system preference, so
  this workflow is consistent for GOBI orders even if other (non-GOBI)
  acquisitions workflows on the same Koha instance use a different
  `AcqCreateItem` setting.
