package Koha::Plugin::Com::Theke::GOBI;

# Copyright 2018 Theke Solutions
#
# This file is part of koha-plugin-gobi.
#
# koha-plugin-gobi is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# koha-plugin-gobi is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with koha-plugin-gobi; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use utf8;

use base qw(Koha::Plugins::Base);

use C4::Acquisition;
use C4::Auth;
use C4::Biblio qw/AddBiblio GetMarcBiblio/;
use C4::Items;
use C4::Context;
use C4::Matcher;

use Koha::Acquisition::Booksellers;
use Koha::Biblios;
use Koha::Acquisition::Baskets;
use Koha::Acquisition::Currencies;
use Koha::Items;
use Koha::ItemTypes;
use Koha::Libraries;
use Koha::Number::Price;

use Koha::Plugin::Com::Theke::GOBI::PurchaseOrder;
use Koha::Plugin::Com::Theke::GOBI::Exception;

use Mojo::JSON qw(decode_json);
use Try::Tiny;

use MARC::Record;

## Here we set our plugin version
our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'GOBI integration',
    author          => 'Tomas Cohen Arazi',
    description     => 'Integrates GOBI with Koha',
    date_authored   => '2017-05-10',
    date_updated    => '2020-03-24',
    minimum_version => '19.1100000',
    maximum_version => undef,
    version         => $VERSION,
};

use Exception::Class (
    'GOBI::Exception'
);

=head1 METHODS

=cut

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $step = $cgi->param('step') // 'list';

    if ( $step eq 'list' ) {
        $self->_list_orders();
    }
    elsif ( $step eq 'add' ) {
        $self->_add_order();
    }
    elsif ( $step eq 'get' ) {
        $self->_get_order();
    }
    elsif ( $step eq 'configure' ) {
        $self->_configure();
    }
    else {
        # $step eq 'render'
        $self->_list_orders();
    }
}

=head2 response_sucess

This method generates a valid success response for GOBI.

$self->response_error({ order_id => 123456 });

=head3 Response:

    <?xml version="1.0" encoding="UTF-8"?>
    <Response>
        <PoLineNumber>123456</PoLineNumber>
    </Response>

=cut

sub response_success {
    my ( $self, $params ) = @_;

    my $cgi = $self->{ cgi };
    print $cgi->header(
        -type     => 'text/xml',
        -charset  => 'UTF-8',
        -encoding => 'UTF-8'
    );
    say "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
    say "<Response>";
    say "    <PoLineNumber>" . $params->{ order_id } . "</PoLineNumber>";
    say "</Response>";
    exit;
}

=head2 response_error

This method generates a valid error response for GOBI.

$self->response_error({ error_code => 'API_KEY_ERROR',
                        error_description => 'Invalid API key' });

=head3 Response:

    <?xml version="1.0" encoding="UTF-8"?>
    <Response>
        <Error>
            <Code>API_KEY_ERROR</Code>
            <Message>Invalid API key</Message>
        </Error>
    </Response>

=cut

sub response_error {
    my ( $self, $params ) = @_;

    my $cgi = $self->{cgi};
    print $cgi->header(
        -type     => 'text/xml',
        -charset  => 'UTF-8',
        -encoding => 'UTF-8'
    );
    say "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
    say "<Response>";
    say "    <Error>";
    say "        <Code>" . $params->{ error_code } . "</Code>";
    say "        <Message>" . $params->{ error_description } . "</Message>";
    say "    </Error>";
    say "</Response>";
    exit;
}

=head2 api_key_valid

This class method validates the passed API key against the stored one.

my $ret = $self->api_key_valid( $passed_api_key );

=cut

sub api_key_valid {
    my ( $self, $api_key ) = @_;

    my $ret;

    if ( defined $api_key ) {
        my $gobi_api_key = $self->retrieve_data( 'api_key' );

        if ( $api_key eq $gobi_api_key ) {
            $ret = 1;
        }
    }

    return $ret;
}

=head2 add_order

Given a raw GOBI order, go through the whole acquisitions workflow

my $order_id = $self->add_order( $raw_gobi_order );

=cut

sub add_order {
    my ( $self, $raw_gobi_order ) = @_;

    my $cgi = $self->{cgi};
    my $gobi_order;
    my $gobi_order_id;
    my $koha_order;

    my @itemnumbers;

    my $schema = Koha::Database->new()->schema();
    $schema->storage->txn_begin();

    my $result = try {
        # Parse the raw purchase order
        $gobi_order = Koha::Plugin::Com::Theke::GOBI::PurchaseOrder->new($raw_gobi_order);

        my $quantity = $gobi_order->OrderDetail->{Quantity} // 0;

        # Should Electronic resources create items?
        my  $create_item_for_electronic_resources = $self->retrieve_data('create_item_for_electronic_resources');
        my $create_items = (!$create_item_for_electronic_resources and $gobi_order->is_electronic)
                                ? 0
                                : 1;

        # Some basic checks for data health
        my $fund_id   = $self->_check_fund_code($gobi_order);

        my $patron_id = $self->retrieve_data('patron_id');
        my $patron    = Koha::Patrons->find($patron_id);
        GOBI::Exception->throw( error => "Invalid configuration (patron_id)" )
            unless $patron;

        # There are side effects in AddBiblio and Koha::Acquisition::Order->store
        # that will read the 'number' param in userenv to set the biblio and order creator.
        # It can be passed explicitly in $order->store, but not in AddBiblio.
        C4::Context->set_userenv( $patron_id );

        # GOBI has VendorCode, but we need Koha's vendor id, which we have already
        my $vendor_id = $self->retrieve_data('vendor_id');
        my $vendor = Koha::Acquisition::Booksellers->find( $vendor_id );
        GOBI::Exception->throw( error => "Invalid configuration (vendor_id)" )
            unless $vendor;

        my $currency  = $self->_check_currency($gobi_order);
        my $price     = $gobi_order->OrderDetail->{ListPriceAmount} // 0;
        my $library   = $self->_check_library_code($gobi_order);

        # Create a basket
        my $basket_id = C4::Acquisition::NewBasket(
            $vendor_id,             # booksellerid
            $patron_id,             # authorisedby
            $gobi_order
              ->OrderDetail
              ->{YBPOrderKey},      # basketname
            q{},                    # basketnote
            q{},                    # basketbooksellernote
            q{},                    # basketcontractnumber
            $library,               # deliveryplace
            $library,               # billingplace
            undef,                  # is_standing
            ($create_items)
                ? 'ordering'
                : undef             # create_items
        );

        # Store on the plugin table TODO: Figure what we would really need
        $gobi_order_id = $self->_store_gobi_order( $gobi_order, $basket_id, $raw_gobi_order );

        # Add biblio
        my ( $biblionumber, $biblioitemnumber ) = $self->_add_biblio($gobi_order);

        my $order_data = {
            biblionumber               => $biblionumber,
            basketno                   => $basket_id,
            created_by                 => $patron_id,
            budget_id                  => $fund_id,
            listprice                  => $price,
            quantity                   => $quantity,
            quantityreceived           => 0,
            order_vendornote           => $gobi_order->OrderDetail->{OrderNotes},
            order_internalnote         => $gobi_order->selector_notes,
            sort1                      => $self->order_type_to_sort_value( $gobi_order, 'sort1' ),
            sort2                      => $self->order_type_to_sort_value( $gobi_order, 'sort2' ),
            currency                   => $currency,
            suppliers_reference_number => $gobi_order->OrderDetail->{YBPOrderKey}
        };
        $order_data = $self->_add_price_data( $vendor_id, $price, $quantity, $order_data );

        $koha_order = Koha::Acquisition::Order->new($order_data);
        $koha_order->store;
        $koha_order->discard_changes; # reload from DB

        if ( $create_items && $quantity > 0 )
        {
            for ( my $i = 0; $i < $quantity; $i++ ) {
                my $item_data = $self->_generate_item_data( $gobi_order, $vendor_id, $price );

                my $itemnumber;
                if ( C4::Context->preference('Version') ge '20.050000' ) {
                    $item_data->{biblionumber}     = $biblionumber;
                    $item_data->{biblioitemnumber} = $biblioitemnumber;
                    my $item_obj = Koha::Item->new( $item_data );
                    $item_obj->store->discard_changes;
                    $itemnumber = $item_obj->itemnumber;
                }
                else {
                    ( undef, undef, $itemnumber ) = C4::Items::AddItem( $item_data, $biblionumber );
                }

                push @itemnumbers, $itemnumber;
                $koha_order->add_item($itemnumber);
            }
        }

        if ( C4::Context->preference('Version') ge '20.110000' ) {
            my $basket = Koha::Acquisition::Baskets->find( $basket_id );
            $basket->close();
        }
        else {
            C4::Acquisition::CloseBasket( $basket_id );
        }

        $schema->storage->txn_commit;
        # All good, return ordernumber
        return $koha_order->ordernumber;
    }
    catch {
        # Problem found, rollback transaction, notify error
        $schema->storage->txn_rollback();
        if ( $_->isa('GOBI::Exception') ) {
            $_->rethrow();
        }
        else {
            GOBI::Exception->throw( "$_" );
        }
    };

    if ( $result->isa('GOBI::Exception') ) {
        $result->rethrow();
    }
    else {
        return $result;
    }
}

sub _get_order {
    my ( $self, $args ) = @_;

    my $cgi = $self->{cgi};
    my $id  = $cgi->param('gobi_order_id');

    my $template = $self->get_template( { file => 'order_details.tt' } );

    my $gobi_order;

    try {
        $gobi_order = $self->_get_gobi_order($id);
    }
    catch {
        if ( $_->isa('Koha::Plugin::Com::Theke::GOBI::Exception') ) {
            $template->param( error => $_->error );
        }
        else {
            $template->param( error => $_ );
        }
    };

    $template->param(
        gobi_order => $gobi_order,
        gpo_id     => $id
    );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
}

sub _list_orders {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    my $template = $self->get_template( { file => 'main.tt' } );

    # Fetch from DB marching a criteria
    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        SELECT * FROM $table
    " );

    $sth->execute();
    my $gobi_orders = $sth->fetchall_arrayref( {} );

    $template->param(
        gobi_orders => $gobi_orders,
    );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
}

sub _store_gobi_order {
    my ( $self, $gobi_order, $basketno, $raw ) = @_;

    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        INSERT INTO $table
               ( status, basketno, raw_msg )
        VALUES ( ?,      ?,        ? )
    " );

    $sth->execute( 'processed', $basketno, $raw );

    my $gpo_id = C4::Context->dbh->{'mysql_insertid'};

    return $gpo_id;
}

sub _update_order_status {
    my ( $self, $gpo_id, $status ) = @_;

    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        UPDATE $table
        SET status=?
        WHERE id=?
    " );

    $sth->execute( $status, $gpo_id );

    return $self;
}

sub _get_gobi_order {
    my ( $self, $id ) = @_;
    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        SELECT raw_msg
        FROM $table
        WHERE id=?
    " );
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref();
    my $gpo;
    try {
        $gpo = Koha::Plugin::Com::Theke::GOBI::PurchaseOrder->new( $row->{raw_msg} );
        return $gpo;
    }
    catch {
        return;
    };
}

sub _add_biblio {

    my ( $self, $gobi_order ) = @_;

    my $record    = $gobi_order->{record};
    my $itemtype  = $self->_check_item_type($gobi_order);
    my $field_942 = $record->field('942');

    my @subfields;
    push @subfields, 'c' => $itemtype;

    if ( $gobi_order->is_electronic ) {
        # is electronic, suppress
        push @subfields, 'n' => '1';
    }

    if ($field_942) {
        # existing fields, auto-vivifies subfield if doesn't exist
        # https://metacpan.org/pod/MARC::Field#update()
        $field_942->update( @subfields );
    }
    else {
        # new field
        $field_942 = MARC::Field->new( '942', ' ', ' ', @subfields );
        $record->insert_fields_ordered( $field_942 );
    }

    my ( $biblionumber, $biblioitemnumber ) = AddBiblio( $record, '' );

    return ( $biblionumber, $biblioitemnumber );
}

sub _generate_item_data {
    my ( $self, $gobi_order, $vendor_id, $price ) = @_;

    my $library_id = $self->_check_library_code($gobi_order);
    my $item_type  = $self->_check_item_type($gobi_order);
    my $not_loan   = $self->retrieve_data('not_loan') // -5 ;

    my $item_data = {
        booksellerid     => $vendor_id,
        cn_source        => C4::Context->preference('DefaultClassificationSource'),
        cn_sort          => q{},
        holdingbranch    => $library_id,
        homebranch       => $library_id,
        itype            => $item_type,
        location         => $gobi_order->shelving_location // q{},
        notforloan       => $not_loan,
        price            => $price,
        replacementprice => $price
    };

    $item_data->{itemnotes_nonpublic} = $gobi_order->selector_notes // q{}
        if $self->retrieve_data( 'add_nonpublic_item_notes' );

    return $item_data;
}

sub _add_price_data {
    my ( $self, $bookseller_id, $price, $quantity, $order_data ) = @_;

    my $bookseller      = Koha::Acquisition::Booksellers->find($bookseller_id);
    my $active_currency = Koha::Acquisition::Currencies->get_active;

    # Unformat price
    $price = Koha::Number::Price->new($price)->unformat;

    # Get tax and discounts info from the vendor
    my $tax_rate = $bookseller->tax_rate;
    my $discount = $bookseller->discount // 0;
    my $THE_discount = $discount / 100;

    $order_data->{tax_rate} = $tax_rate;
    $order_data->{discount} = $THE_discount;

    if ($price) {
        if ( $bookseller->listincgst ) {

            # Vendor includes GST
            $order_data->{ecost} = $price * ( 1 - $discount );
            $order_data->{rrp} = $price;
        }
        else {
            $order_data->{rrp} = $price / ( 1 + $order_data->{tax_rate} );
            $order_data->{ecost} = $order_data->{rrp} * ( 1 - $discount );
        }
        $order_data->{listprice} = $order_data->{rrp} / $active_currency->rate;
        $order_data->{unitprice} = $order_data->{ecost};
        $order_data->{total}     = $order_data->{ecost} * $quantity;
    }
    else {
        $order_data->{listprice} = 0;
    }

    $order_data = C4::Acquisition::populate_order_with_prices(
        {   order        => $order_data,
            booksellerid => $bookseller_id,
            ordering     => 1,
            receiving    => 1,
        }
    );

    return $order_data;
}

sub _check_fund_code {
    my ( $self, $gobi_order ) = @_;

    my $schema = Koha::Database->new()->schema();

    # We actually call it fund
    my $budget_code = $gobi_order->OrderDetail->{FundCode};

    # Check budget is active !
    my $period_rs = $schema->resultset('Aqbudgetperiod')->search( { budget_period_active => 1, } );

    # Check the fund code exists and is active
    my $budget = $schema->resultset('Aqbudget')->single(
        {   budget_code      => $budget_code,
            budget_period_id => { -in => $period_rs->get_column('budget_period_id')->as_query },
        }
    );

    if ( !defined $budget ) {

        # Raise an exception the passed fund is not valid
        GOBI::Exception->throw("Fund code $budget_code is invalid");
    }

    return $budget->id;
}

sub _check_library_code {
    my ( $self, $gobi_order ) = @_;

    # We actually call it fund
    my $library_id = $gobi_order->OrderDetail->{Location};

    GOBI::Exception->throw("Missing library id.")
        unless defined $library_id;

    GOBI::Exception->throw("Invalid library code passed ($library_id)")
        unless Koha::Libraries->find($library_id);

    return $library_id;
}

sub _check_currency {
    my ( $self, $gobi_order ) = @_;

    # We actually call it fund
    my $currency = $gobi_order->OrderDetail->{ListPriceCurrency};

    GOBI::Exception->throw("Missing currency code.")
        unless defined $currency;

    GOBI::Exception->throw("Invalid currency passed ($currency)")
        unless Koha::Acquisition::Currencies->find($currency);

    return $currency;
}

sub _check_item_type {
    my ( $self, $gobi_order ) = @_;

    my $item_type = $gobi_order->item_type;

    GOBI::Exception->throw("Missing item type.")
        unless defined $item_type;

    GOBI::Exception->throw("Invalid item type passed ($item_type)")
        unless Koha::ItemTypes->find($item_type);

    return $item_type;
}

sub _table_exists {
    my $table = shift;
    eval {
        C4::Context->dbh->{PrintError} = 0;
        C4::Context->dbh->{RaiseError} = 1;
        C4::Context->dbh->do(qq{SELECT * FROM $table WHERE 1 = 0 });
    };
    return 1 unless $@;
    return 0;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    my $template = $self->get_template({ file => 'configure.tt' });

    my $api_key   = $self->retrieve_data( 'api_key'   );
    my $vendor_id = $self->retrieve_data( 'vendor_id' );
    my $patron_id = $self->retrieve_data( 'patron_id' );
    my $not_loan  = $self->retrieve_data( 'not_loan'  );
    my $lpm_sort1 = $self->retrieve_data( 'lpm_sort1' );
    my $lpm_sort2 = $self->retrieve_data( 'lpm_sort2' );
    my $upm_sort1 = $self->retrieve_data( 'upm_sort1' );
    my $upm_sort2 = $self->retrieve_data( 'upm_sort2' );
    my $lps_sort1 = $self->retrieve_data( 'lps_sort1' );
    my $lps_sort2 = $self->retrieve_data( 'lps_sort2' );
    my $ups_sort1 = $self->retrieve_data( 'ups_sort1' );
    my $ups_sort2 = $self->retrieve_data( 'ups_sort2' );
    my $lem_sort1 = $self->retrieve_data( 'lem_sort1' );
    my $lem_sort2 = $self->retrieve_data( 'lem_sort2' );
    my $les_sort1 = $self->retrieve_data( 'les_sort1' );
    my $les_sort2 = $self->retrieve_data( 'les_sort2' );
    my $create_item_for_electronic_resources = $self->retrieve_data( 'create_item_for_electronic_resources' );
    my $add_nonpublic_item_notes = $self->retrieve_data( 'add_nonpublic_item_notes' );

    $template->param(
        api_key   => $api_key,
        vendor_id => $vendor_id,
        patron_id => $patron_id,
        not_loan  => $not_loan,
        lpm_sort1 => $lpm_sort1,
        lpm_sort2 => $lpm_sort2,
        upm_sort1 => $upm_sort1,
        upm_sort2 => $upm_sort2,
        lps_sort1 => $lps_sort1,
        lps_sort2 => $lps_sort2,
        ups_sort1 => $ups_sort1,
        ups_sort2 => $ups_sort2,
        lem_sort1 => $lem_sort1,
        lem_sort2 => $lem_sort2,
        les_sort1 => $les_sort1,
        les_sort2 => $les_sort2,
        create_item_for_electronic_resources => $create_item_for_electronic_resources,
        add_nonpublic_item_notes => $add_nonpublic_item_notes
    );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
}

sub _configure {
    my ( $self, $args ) = @_;

    my $cgi       = $self->{cgi};
    my $api_key   = $cgi->param('api_key');
    my $vendor_id = $cgi->param('vendor_id');
    my $patron_id = $cgi->param('patron_id');
    my $not_loan  = $cgi->param('not_loan');

    my $lpm_sort1 = $cgi->param('lpm_sort1') // q{};
    my $lpm_sort2 = $cgi->param('lpm_sort2') // q{};
    my $upm_sort1 = $cgi->param('upm_sort1') // q{};
    my $upm_sort2 = $cgi->param('upm_sort2') // q{};
    my $lps_sort1 = $cgi->param('lps_sort1') // q{};
    my $lps_sort2 = $cgi->param('lps_sort2') // q{};
    my $ups_sort1 = $cgi->param('ups_sort1') // q{};
    my $ups_sort2 = $cgi->param('ups_sort2') // q{};
    my $lem_sort1 = $cgi->param('lem_sort1') // q{};
    my $lem_sort2 = $cgi->param('lem_sort2') // q{};
    my $les_sort1 = $cgi->param('les_sort1') // q{};
    my $les_sort2 = $cgi->param('les_sort2') // q{};
    my $create_item_for_electronic_resources = $cgi->param('create_item_for_electronic_resources') // 0;
    my $add_nonpublic_item_notes = $cgi->param('add_nonpublic_item_notes') // 0;


    # Store new API key
    $self->store_data({ 'api_key'   => $api_key   });
    $self->store_data({ 'vendor_id' => $vendor_id });
    $self->store_data({ 'patron_id' => $patron_id });
    $self->store_data({ 'not_loan'  => $not_loan  });
    $self->store_data({ 'lpm_sort1' => $lpm_sort1 });
    $self->store_data({ 'lpm_sort2' => $lpm_sort2 });
    $self->store_data({ 'upm_sort1' => $upm_sort1 });
    $self->store_data({ 'upm_sort2' => $upm_sort2 });
    $self->store_data({ 'lps_sort1' => $lps_sort1 });
    $self->store_data({ 'lps_sort2' => $lps_sort2 });
    $self->store_data({ 'ups_sort1' => $ups_sort1 });
    $self->store_data({ 'ups_sort2' => $ups_sort2 });
    $self->store_data({ 'lem_sort1' => $lem_sort1 });
    $self->store_data({ 'lem_sort2' => $lem_sort2 });
    $self->store_data({ 'les_sort1' => $les_sort1 });
    $self->store_data({ 'les_sort2' => $les_sort2 });
    $self->store_data({ 'create_item_for_electronic_resources' => $create_item_for_electronic_resources });
    $self->store_data({ 'add_nonpublic_item_notes' => $add_nonpublic_item_notes });

    $self->_list_orders();
}

sub order_type_to_sort_value {
    my ( $self, $order, $sort ) = @_;

    my $sort_mapping = {
        ListedPrintMonograph      => 'lpm',
        UnlinstedPrintMonograph   => 'upm',
        ListedPrintSerial         => 'lps',
        UnlinstedPrintSerial      => 'ups',
        ListedElectronicMonograph => 'lem',
        ListedElectronicSerial    => 'les'
    };

    die "Invalid order type " . $order->type
        unless exists $sort_mapping->{ $order->type };

    my $variable = $sort_mapping->{ $order->type } . "_$sort";
    my $value    = $self->retrieve_data( $variable ) // q{};

    return $value;
}

sub install {
    my ( $self, $args ) = @_;

    my $po_table = $self->get_qualified_table_name('purchase_orders');

    C4::Context->dbh->do("
        CREATE TABLE $po_table (
          `id` INT(11) NOT NULL auto_increment,
          `status` TEXT,
          `basketno` INT(11) REFERENCES aqbasket( basketno),
          `raw_msg` MEDIUMTEXT,
          `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY  (id),
          KEY basketno ( basketno),
          CONSTRAINT gobipo_basketno FOREIGN KEY ( basketno ) REFERENCES aqbasket ( basketno ) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    ") unless $self->_table_exists($po_table);

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $database_version = $self->retrieve_data('__INSTALLED_VERSION__') || 0;

    if ( $self->_version_compare( $database_version, "1.3.0" ) == -1 ) {

        my $po_table = $self->get_qualified_table_name('purchase_orders');

        C4::Context->dbh->do(qq{
            ALTER TABLE $po_table
                ADD COLUMN `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                AFTER `raw_msg`;
        });

        $self->store_data({ '__INSTALLED_VERSION__' => "1.3.0" });
    }

    if ( $self->_version_compare( $database_version, "2.0.1" ) == -1 ) {

        # Keep current behavior by default
        $self->store_data( { 'create_item_for_electronic_resources' => 0 } );

        $self->store_data( { '__INSTALLED_VERSION__' => "2.0.1" } );
    }

    if ( $self->_version_compare( $database_version, "2.0.2" ) == -1 ) {

        # Keep current behavior by default
        $self->store_data( { 'add_nonpublic_item_notes' => 0 } );

        $self->store_data( { '__INSTALLED_VERSION__' => "2.0.2" } );
    }

    return 1;
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'gobi';
}

sub uninstall {
    my ( $self, $args ) = @_;

    return 1;
}

1;
