# Koha GOBI integration plugin

## Introduction

This plugin is designed to provide an easy integration for the _GOBI Library Solutions from EBSCO_.
It registers purchase orders into _Koha_ based on the GOBI message it receives

It is intended to serve as a testbed so the feature can get into _Koha_'s source code.

_GOBI_ messages include a basic MARC21 record for the purchased item(s). This MARC21 record is looked
up in _Koha_ for matches based on ISBN. If there's a match, the generated purchase basket is correctly
linked with the already existing record. Otherwise, the concise one is added to _Koha_.

It follows the implicit _Koha_ workflow, which includes:
1. Parse GOBI purchase order.
2. Verify mandatory data is present and valid.
3. Create a purchase basket.
4. Store the GOBI order in the plugin's table, including the basketno
5. Deal with MARC data. It implies checking for duplicates:
..*There's a match, then use it.
..*Add MARC record
6. Add the required items (based on _quantity_) if **AcqCreateItem** is set to ordering.
7. Create an order, attach the items
8. Close the purchase basket

## Installing

## Using

In order to use the plugin, a vendor needs to be created and properly configured following
_GOBI_'s representatives advise (tax included?, tax rate?, etc). Some of this info might be
hardcoded at some point if it's always the same, for simplicity. The approach was to make it
as general as possible.

_GOBI_ provides a way to create local data fields for messages. This plugin requires some
to be defined and included on the message:

* Vendor code: As mentioned above, you need to create a vendor for EBSCO. Its ID needs to be
  provided for generating the **VendorCode** LocalData field.
* Fund codes: In Koha you create a _budget_ and then split it into _funds_. You need to provide
  _GOBI_ with your fund codes list to link purchase orders and specific funds. It will be used
  in the **FundCode** tag.
* Library code: In _Koha_, the **branchcode** is used to identify different libraries/branches.
  _GOBI_ needs to know those codes to properly set the _homebranch_ and _holdingbranch_ for the
  generated items. It will be used to generate the local data field **Library**.
* Currency: _GOBI_ only provides **USD** and **GBP** for currency codes. They need to be properly
  set in _Koha_, and have their exchange rates set too.

### TL;DR

The following local data fields need to be set in _GOBI_:
* **VendorCode**, filled with the vendor ID for _GOBI_.
* **Library**, needs to be generated in _GOBI_ with branch/library information.

And _funds_ codes need to be provided to _GOBI_ and they will be used on generating the _GOBI_ messages.

## TODO

* Revisit the plugin table structure, probably add a config table for storing preferences.
* The record matching algorithm could be configurable. This is related to the above item on this list.
* HEA shows most people have **AcqCreateItem** set to _ordering_, but there are others that don't.
  This should be discussed with someone more familiar with acquisitions workflow.
* It is not clear if GOBI price includes taxes, and which percentage.
* There might be some discount applied that is not included on the GOBI message.
* Is budget enough? Do we need to handle that?
* Authentication we currently only support cookie authentication, which is not enough.
  a hook to the plugins handling system could be needed. Or move it into _Koha_ proper
  (caveat: _Koha_'s REST api doesn't provide a way to do this either).

## License

See the LICENSE file on the root directory.
