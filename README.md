# Koha GOBI integration plugin

## Introduction

This plugin is designed to provide an easy integration for the _GOBI Library Solutions from EBSCO_.
It registers purchase orders into _Koha_ based on the GOBI message it receives

It is intended to serve as a testbed so the feature can get into _Koha_'s source code.

_GOBI_ messages include a basic MARC21 record for the purchased item(s). This MARC21 record is added to
_Koha_ and linked to the generated purchase.

It follows the implicit _Koha_ workflow, which includes:
1. Parse GOBI purchase order.
2. Verify the GOBI order includes mandatory data and valid.
3. Create a purchase basket.
4. Store the GOBI order in the plugin's table, including the basketno
5. Add MARC record
6. Add the required items (based on _quantity_) if **AcqCreateItem** is set to ordering.
7. Create an order, attach the items
8. Close the purchase basket

## Install and setup

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart _memcached_:
```
$ sudo systemctl restart memcached.service
```
* Restart _koha-common_:
```
$ sudo systemctl restart koha-common.service
```

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will
see the Tools Plugins.

Download the .kpz file from the [releases page](https://gitlab.com/thekesolutions/plugins/koha-plugin-gobi/-/releases).
Then upload the _kpz_ file in the plugins administration page.

Then restart _koha-common_ again:
```
$ sudo systemctl restart koha-common.service
```

You can test it is accessible using _curl_ like this from the command line:
```
vagrant@kohadevbox:~$ curl http://localhost:8080/api/v1/gobi/orders
<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Error>
        <Code>API_KEY_MISSING</Code>
        <Message>API Key parameter missing on request.</Message>
    </Error>
</Response>
```

If you get a response from the api, you are on the right track.

### Deprecated setup

If your Koha is too old (prior to 18.11), you need to upgrade it :-D But you can still set the old
CGI script for GOBI:

You need to tweak your _Apache_ vhost configuration for the intranet. If you are using the packages
install method (you should!) given the instance name **instance** you need to edit the
_/etc/apache2/sites-available/**instance**.conf_ file. Look for the intranet vhost and add this:

```
ScriptAlias /gobi "/var/lib/koha/instance/plugins/Koha/Plugin/Com/Theke/GOBI/gobi"
Alias /plugin "/var/lib/koha/instance/plugins"
<Directory /var/lib/koha/mykoha/plugins>
      Options Indexes FollowSymLinks
      AllowOverride None
      Require all granted
</Directory>
Then restart _koha-common_ again:
```

Then restart _apache_:
```
$ sudo systemctl restart apache2.service
```

## Configure the plugin

* Create a **GOBI vendor** in Koha. Pick the vendor id (*booksellerid* on the URL).
* Go to the plugin configuration page. Put the *vendor id* on the **GOBI vendor id** field.
* Generate an API key by clicking on the refresh icon.
* Set the 'Not for loan' value to suit your needs.
* Save.

## Configure GOBI

Your GOBI representative will require the following information:

* The generated **API key**
* The URL for your **staff client** (HTTPS is mandatory for security reasons)

You will need to send GOBI some CSV files, each containing:

* **branchcode** and **branchname** (for use in *Location*).
* **fund ids** and **fund names** (for use in *FundCode*).
* **item type ids** and **item type descriptions** (for use in *Local Data 1*).
* **shelving location codes** and **shelving location descriptions** (for use in *Local Data 2*).

### Currencies

_GOBI_ handles **USD** and **GBP** as currency codes. They need to be set likewise in Koha.

## TODO

* _GOBI_ only accepts the *<POLineNumber>* value in the response message. Because of this, and in order
  to be able to match the full record using 999$c later (once the full record is submitted), the plugin 
  returns the resulting **biblionumber** on that field until _GOBI_ accepts more information to be returned.
* It is not clear if _GOBI_ price includes taxes, and which percentage.
* There might be some discount applied that is not included on the GOBI message.
* We are not checking if funds are enough and what to do in that case.
* _GOBI_ orders visualization needs some love, based on users input.

## License

See the LICENSE file on the root directory.
