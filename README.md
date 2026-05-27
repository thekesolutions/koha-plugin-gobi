# Koha GOBI Integration Plugin

[![CI](https://github.com/thekesolutions/koha-plugin-gobi/actions/workflows/main.yml/badge.svg)](https://github.com/thekesolutions/koha-plugin-gobi/actions/workflows/main.yml)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/thekesolutions/koha-plugin-gobi)](https://github.com/thekesolutions/koha-plugin-gobi/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Introduction

This plugin provides integration with _GOBI Library Solutions from EBSCO_ for automated acquisitions workflow. It processes purchase orders from GOBI and creates corresponding records in Koha.

_GOBI_ messages include a basic MARC21 record for purchased items. This record is added to Koha and linked to the generated purchase order.

The plugin follows the standard Koha acquisitions workflow:
1. Parse GOBI purchase order
2. Verify order data and validity
3. Create a purchase basket
4. Store the GOBI order in the plugin's table
5. Add MARC record
6. Add required items (based on quantity) if **AcqCreateItem** is set to ordering
7. Create an order and attach items
8. Close the purchase basket

## Installation

### Method 1: Plugin Search (Recommended)

If your system administrator has configured Theke's GitHub organization in `koha-conf.xml`:

1. Go to **Administration → Plugins**
2. Search for "gobi"
3. Install directly from the search results

### Method 2: Manual Download

1. Download the latest `.kpz` file from the [releases page](https://github.com/thekesolutions/koha-plugin-gobi/releases)
2. Go to **Administration → Plugins**
3. Upload the `.kpz` file
4. Enable the plugin

### System Requirements

Ensure plugins are enabled in your Koha installation:
- Set `<enable_plugins>1</enable_plugins>` in `koha-conf.xml`
- Verify `<pluginsdir>` path exists and is writable
- Restart memcached and koha-common services

## Configuration

### Koha Setup
1. Create a **GOBI vendor** in Koha (note the vendor ID)
2. Create a **GOBI patron** in Koha (note the patron ID)
3. Go to the plugin configuration page
4. Enter the vendor ID in the **GOBI vendor id** field
5. Generate an API key using the refresh icon
6. Configure the 'Not for loan' value as needed
7. Save configuration

### GOBI Setup
Provide your GOBI representative with:
- The generated **API key**
- Your **staff client URL** (HTTPS required)
- CSV files containing:
  - Branch codes and names (for Location)
  - Fund IDs and names (for FundCode)
  - Item type IDs and descriptions (for Local Data 1)
  - Shelving location codes and descriptions (for Local Data 2)

### Currency Requirements
GOBI supports **USD** and **GBP** currency codes. Ensure these are configured in Koha.

### Record Matching Rules (ISBN / OCLC)

The plugin can detect duplicate records before creating new ones. When a GOBI order arrives, the incoming MARC record is compared against your catalog using Koha's matching rules. This avoids creating duplicate bibliographic records for titles you already own.

#### Setting up a matching rule in Koha

1. Go to **Administration → Record matching rules**
2. Click **New record matching rule**
3. Fill in:
   - **Matching rule code**: e.g. `ISBN` or `OCLC`
   - **Description**: e.g. "Match on ISBN" or "Match on OCLC number"
   - **Match threshold**: `1000`
4. Add a **match point**:

   | Field | For ISBN matching | For OCLC matching |
   |-------|-------------------|-------------------|
   | Search index | `isbn` | `Other-control-number` |
   | Score | `1000` | `1000` |
   | Tag | `020` | `035` |
   | Subfields | `a` | `a` |

5. Save the matching rule

#### Configuring the plugin to use matching

1. Go to the **GOBI plugin configuration** page
2. In the **Record matching rule** dropdown, select the rule you created
3. Choose the **Match action**:
   - **Create new record** — ignore matches, always create a new biblio (default)
   - **Overlay existing record** — replace the matched record with the incoming GOBI record
   - **Use existing record** — keep the existing record untouched and attach the order to it
4. Save configuration

#### How it works

When a GOBI order is received:

1. The plugin extracts the MARC record from the order
2. If a matching rule is configured, it searches for existing records using the configured index (ISBN or OCLC number)
3. If a match is found:
   - **Overlay**: the existing record is updated with the incoming data, and the order is linked to it
   - **Use existing**: the order is linked to the existing record without modifying it
4. If no match is found, a new bibliographic record is created

#### Tips

- **ISBN matching** works best for print monographs where the ISBN in the GOBI record matches your catalog
- **OCLC matching** is useful when your records have 035$a fields with `(OCoLC)` prefixes — this is common for records sourced from WorldCat
- You can only configure one matching rule at a time
- If multiple matches are found, the plugin uses the first (highest-scoring) match and logs a warning

## Testing

Test the API endpoint:
```bash
curl http://your-koha-site/api/v1/gobi/orders
```

Expected response (API key missing error indicates the endpoint is working):
```xml
<Response><Error><Code>API_KEY_MISSING</Code></Error></Response>
```

## Notes

- GOBI only accepts `<POLineNumber>` in response messages
- The plugin returns the **biblionumber** in this field for record matching
- Tax handling and fund availability checking may need customization
- GOBI orders visualization can be enhanced based on user feedback

## Support

- **Issues**: [GitHub Issues](https://github.com/thekesolutions/koha-plugin-gobi/issues)
- **Documentation**: See plugin configuration page in Koha
- **Commercial Support**: [Theke Solutions](https://theke.io)

## License

GPL-3.0-or-later. See the LICENSE file for details.
