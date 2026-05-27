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

use Module::Metadata;
use Koha::Schema;

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s!\.pm$!/lib!;
    unshift @INC, $path;

    require Koha::Schema::Result::KohaPluginComThekeGobiPurchaseOrder;
    Koha::Schema->register_class(
        KohaPluginComThekeGobiPurchaseOrder =>
            'Koha::Schema::Result::KohaPluginComThekeGobiPurchaseOrder'
    );
}

use C4::Acquisition qw(ModBasket NewBasket);
use C4::Auth;
use C4::Biblio qw(AddBiblio ModBiblio);
use C4::Context;
use C4::Installer;
use C4::Items;
use C4::MarcModificationTemplates qw(ModifyRecordWithTemplate);
use C4::Matcher;

use Koha::Acquisition::Booksellers;
use Koha::Biblios;
use Koha::Acquisition::Baskets;
use Koha::Acquisition::Currencies;
use Koha::Exceptions;
use Koha::Items;
use Koha::ItemTypes;
use Koha::Libraries;
use Koha::Number::Price;
use Koha::SearchEngine;
use Koha::SearchEngine::Indexer;

use Koha::Plugin::Com::Theke::GOBI::PurchaseOrder;
use Koha::Plugin::Com::Theke::GOBI::Exception;

use Mojo::JSON qw(decode_json);
use Try::Tiny;

use MARC::Record;

## Here we set our plugin version
our $VERSION = "4.0.0";

our $metadata = {
    name            => 'GOBI integration',
    author          => 'Tomas Cohen Arazi',
    description     => 'Integrates GOBI with Koha',
    date_authored   => '2017-05-10',
    date_updated    => '1970-01-01',
    minimum_version => '22.1100000',
    maximum_version => undef,
    version         => $VERSION,
};

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

    if ( $step eq 'configure' ) {
        $self->_configure();
    } else {
        # Redirect to admin page for all other steps
        $self->admin($args);
    }
}

=head3 admin

Renders the admin page with the API-driven orders table.

=cut

sub admin {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'templates/admin.tt' } );

    print $cgi->header( -type => 'text/html', -charset => 'UTF-8' );
    print $template->output();
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

    my $cgi = $self->{cgi};
    print $cgi->header(
        -type     => 'text/xml',
        -charset  => 'UTF-8',
        -encoding => 'UTF-8'
    );
    say "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
    say "<Response>";
    say "    <PoLineNumber>" . $params->{order_id} . "</PoLineNumber>";
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
    say "        <Code>" . $params->{error_code} . "</Code>";
    say "        <Message>" . $params->{error_description} . "</Message>";
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
        my $gobi_api_key = $self->retrieve_data('api_key');

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
    my ( $biblionumber, $biblioitemnumber );

    my @itemnumbers;

    Koha::Database->new->schema->txn_do(
        sub {

            # Parse the raw purchase order
            $gobi_order = Koha::Plugin::Com::Theke::GOBI::PurchaseOrder->new($raw_gobi_order);

            my $quantity = $gobi_order->OrderDetail->{Quantity} // 0;

            # Should Electronic resources create items?
            my $create_item_for_electronic_resources = $self->retrieve_data('create_item_for_electronic_resources');
            my $create_items =
                ( !$create_item_for_electronic_resources and $gobi_order->is_electronic )
                ? 0
                : 1;

            # Some basic checks for data health
            my $fund_id = $self->check_fund_code($gobi_order->OrderDetail->{FundCode});

            my $patron_id = $self->retrieve_data('patron_id');
            my $patron    = Koha::Patrons->find($patron_id);
            GOBI::Exception->throw( error => "Invalid configuration (patron_id)" )
                unless $patron;

            # There are side effects in AddBiblio and Koha::Acquisition::Order->store
            # that will read the 'number' param in userenv to set the biblio and order creator.
            # It can be passed explicitly in $order->store, but not in AddBiblio.
            C4::Context->set_userenv($patron_id);

            # GOBI has VendorCode, but we need Koha's vendor id, which we have already
            my $vendor_id = $self->retrieve_data('vendor_id');
            my $vendor    = Koha::Acquisition::Booksellers->find($vendor_id);
            GOBI::Exception->throw( error => "Invalid configuration (vendor_id)" )
                unless $vendor;

            my $currency = $self->check_currency($gobi_order->OrderDetail->{ListPriceCurrency});
            my $price    = $gobi_order->OrderDetail->{ListPriceAmount} // 0;
            my $library  = $self->check_library_code( $gobi_order->OrderDetail->{Location} );

            # Create a basket
            my $basket_id = C4::Acquisition::NewBasket(
                $vendor_id,                                 # booksellerid
                $patron_id,                                 # authorisedby
                $gobi_order->OrderDetail->{YBPOrderKey},    # basketname
                q{},                                        # basketnote
                q{},                                        # basketbooksellernote
                q{},                                        # basketcontractnumber
                $library,                                   # deliveryplace
                $library,                                   # billingplace
                undef,                                      # is_standing
                ($create_items)
                ? 'ordering'
                : undef                                     # create_items
            );

            # Attempt to set the managing library
            my $managing_library_id = $gobi_order->managing_library_id;
            $self->set_managing_library( { basket_id => $basket_id, managing_library_id => $managing_library_id } )
                if $managing_library_id;

            # Store on the plugin table TODO: Figure what we would really need
            $gobi_order_id = $self->_store_gobi_order( $gobi_order, $basket_id, $raw_gobi_order );

            # Add biblio
            my $record_action;
            ( $biblionumber, $biblioitemnumber, $record_action ) = $self->_add_biblio($gobi_order);

            # Update the GOBI order record with biblio info
            $self->_update_gobi_order_biblio( $gobi_order_id, $biblionumber, $record_action );

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
            $order_data = $self->_prepare_order_data( $vendor_id, $price, $quantity, $order_data );

            $koha_order = Koha::Acquisition::Order->new($order_data);
            $koha_order->populate_with_prices_for_ordering()->store()->discard_changes();

            if ( $create_items && $quantity > 0 ) {
                for ( my $i = 0 ; $i < $quantity ; $i++ ) {
                    my $item_data = $self->_generate_item_data( $gobi_order, $vendor_id, $price );

                    $item_data->{biblionumber}     = $biblionumber;
                    $item_data->{biblioitemnumber} = $biblioitemnumber;
                    my $item = Koha::Item->new($item_data);
                    $item->store->discard_changes;

                    push @itemnumbers, $item->id;
                    $koha_order->add_item( $item->id );
                }
            }

            my $basket = Koha::Acquisition::Baskets->find($basket_id);
            $basket->close();
        }
    );

    ## All good
    # ask for indexing the record
    my $indexer = Koha::SearchEngine::Indexer->new( { index => $Koha::SearchEngine::BIBLIOS_INDEX } );
    $indexer->index_records( $biblionumber, "specialUpdate", "biblioserver" );

    # return ordernumber
    return $koha_order->ordernumber;
}

sub _store_gobi_order {
    my ( $self, $gobi_order, $basketno, $raw ) = @_;

    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        INSERT INTO $table
               ( status, basketno, order_key, raw_msg )
        VALUES ( ?,      ?,        ?,         ? )
    " );

    $sth->execute( 'processed', $basketno, $gobi_order->OrderDetail->{YBPOrderKey}, $raw );

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

sub _update_gobi_order_biblio {
    my ( $self, $gpo_id, $biblionumber, $record_action ) = @_;

    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        UPDATE $table
        SET biblionumber=?, record_action=?
        WHERE id=?
    " );

    $sth->execute( $biblionumber, $record_action, $gpo_id );

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
    } catch {
        return;
    };
}

sub _add_biblio {

    my ( $self, $gobi_order ) = @_;

    my $record    = $gobi_order->{record};
    my $itemtype  = $self->check_item_type( $gobi_order->item_type );
    my $field_942 = $record->field('942');

    my @subfields;
    push @subfields, 'c' => $itemtype;

    if ( $gobi_order->is_electronic ) {

        # is electronic, suppress
        push @subfields, 'n' => '1';
    }

    if ($field_942) {
        $field_942->update(@subfields);
    } else {
        $field_942 = MARC::Field->new( '942', ' ', ' ', @subfields );
        $record->insert_fields_ordered($field_942);
    }

    # Check for matching records
    my $matcher_id    = $self->retrieve_data('matcher_id');
    my $match_action  = $self->retrieve_data('match_action') // 'create';
    my $record_action = 'created';

    if ( $matcher_id && $match_action ne 'create' ) {
        my $matcher = C4::Matcher->fetch($matcher_id);

        if ($matcher) {
            my @matches = $matcher->get_matches( $record, 1000 );

            if (@matches) {
                my $matched_biblionumber = $matches[0]->{record_id};

                if ( @matches > 1 ) {
                    $self->gobi_warn(
                        sprintf( "Multiple matches (%d) found for incoming record, using biblionumber %d",
                            scalar @matches, $matched_biblionumber )
                    );
                }

                my $biblio = Koha::Biblios->find($matched_biblionumber);

                if ($biblio) {
                    if ( $match_action eq 'overlay' ) {
                        my $marc_mod_template_id = $self->retrieve_data('marc_mod_template');
                        if ($marc_mod_template_id) {
                            try {
                                ModifyRecordWithTemplate( $marc_mod_template_id, $record );
                            } catch {
                                $self->gobi_warn(
                                    sprintf( "Error applying ModifyRecordWithTemplate(%s): %s",
                                        $marc_mod_template_id, $_ )
                                );
                            };
                        }
                        ModBiblio( $record, $matched_biblionumber, '', { skip_record_index => 1 } );
                        $record_action = 'overlayed';
                    } else {
                        # use_existing: keep record untouched
                        $record_action = 'reused';
                    }

                    return ( $matched_biblionumber, $biblio->biblioitem->biblioitemnumber, $record_action );
                }
            }
        }
    }

    # No match or match_action is 'create': add new record
    my $marc_mod_template_id = $self->retrieve_data('marc_mod_template');

    if ($marc_mod_template_id) {
        try {
            ModifyRecordWithTemplate( $marc_mod_template_id, $record );
        } catch {
            $self->gobi_warn(
                sptrintf( "Error applying ModifyRecordWithTemplate(%s): %s", $marc_mod_template_id, $_ ) );
        }
    }

    my ( $biblionumber, $biblioitemnumber ) = AddBiblio( $record, '', { skip_record_index => 1 } );

    return ( $biblionumber, $biblioitemnumber, $record_action );
}

sub _generate_item_data {
    my ( $self, $gobi_order, $vendor_id, $price ) = @_;

    my $library_id = $self->check_library_code( $gobi_order->OrderDetail->{Location} );
    my $item_type  = $self->check_item_type( $gobi_order->item_type );
    my $not_loan   = $self->retrieve_data('not_loan') // -5;

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
        if $self->retrieve_data('add_nonpublic_item_notes');

    return $item_data;
}

sub _prepare_order_data {
    my ( $self, $bookseller_id, $price, $quantity, $order_data ) = @_;

    my $bookseller      = Koha::Acquisition::Booksellers->find($bookseller_id);
    my $active_currency = Koha::Acquisition::Currencies->get_active;

    # Unformat price
    $price = Koha::Number::Price->new($price)->unformat;

    # Get tax and discounts info from the vendor
    my $tax_rate     = $bookseller->tax_rate;
    my $discount     = $bookseller->discount // 0;
    my $THE_discount = $discount / 100;

    $order_data->{tax_rate} = $tax_rate;
    $order_data->{discount} = $THE_discount;

    if ($price) {
        if ( $bookseller->listincgst ) {

            # Vendor includes GST
            $order_data->{ecost} = $price * ( 1 - $discount );
            $order_data->{rrp}   = $price;
        } else {
            $order_data->{rrp}   = $price / ( 1 + $order_data->{tax_rate} );
            $order_data->{ecost} = $order_data->{rrp} * ( 1 - $discount );
        }
        $order_data->{listprice} = $order_data->{rrp} / $active_currency->rate;
        $order_data->{unitprice} = $order_data->{ecost};
        $order_data->{total}     = $order_data->{ecost} * $quantity;
    } else {
        $order_data->{listprice} = 0;
    }

    return $order_data;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    my $saved = $args->{saved} // 0;

    my $template = $self->get_template( { file => 'templates/configure.tt' } );

    my $api_key                              = $self->retrieve_data('api_key');
    my $vendor_id                            = $self->retrieve_data('vendor_id');
    my $patron_id                            = $self->retrieve_data('patron_id');
    my $not_loan                             = $self->retrieve_data('not_loan');
    my $lpm_sort1                            = $self->retrieve_data('lpm_sort1');
    my $lpm_sort2                            = $self->retrieve_data('lpm_sort2');
    my $upm_sort1                            = $self->retrieve_data('upm_sort1');
    my $upm_sort2                            = $self->retrieve_data('upm_sort2');
    my $lps_sort1                            = $self->retrieve_data('lps_sort1');
    my $lps_sort2                            = $self->retrieve_data('lps_sort2');
    my $ups_sort1                            = $self->retrieve_data('ups_sort1');
    my $ups_sort2                            = $self->retrieve_data('ups_sort2');
    my $lem_sort1                            = $self->retrieve_data('lem_sort1');
    my $lem_sort2                            = $self->retrieve_data('lem_sort2');
    my $les_sort1                            = $self->retrieve_data('les_sort1');
    my $les_sort2                            = $self->retrieve_data('les_sort2');
    my $marc_mod_template                    = $self->retrieve_data('marc_mod_template');
    my $create_item_for_electronic_resources = $self->retrieve_data('create_item_for_electronic_resources');
    my $add_nonpublic_item_notes             = $self->retrieve_data('add_nonpublic_item_notes');
    my $matcher_id                           = $self->retrieve_data('matcher_id');
    my $match_action                         = $self->retrieve_data('match_action') // 'create';

    # Fetch available matching rules for the dropdown
    my @matchers = C4::Matcher::GetMatcherList();

    $template->param(
        api_key                              => $api_key,
        vendor_id                            => $vendor_id,
        patron_id                            => $patron_id,
        not_loan                             => $not_loan,
        lpm_sort1                            => $lpm_sort1,
        lpm_sort2                            => $lpm_sort2,
        upm_sort1                            => $upm_sort1,
        upm_sort2                            => $upm_sort2,
        lps_sort1                            => $lps_sort1,
        lps_sort2                            => $lps_sort2,
        ups_sort1                            => $ups_sort1,
        ups_sort2                            => $ups_sort2,
        lem_sort1                            => $lem_sort1,
        lem_sort2                            => $lem_sort2,
        les_sort1                            => $les_sort1,
        les_sort2                            => $les_sort2,
        create_item_for_electronic_resources => $create_item_for_electronic_resources,
        add_nonpublic_item_notes             => $add_nonpublic_item_notes,
        marc_mod_template                    => $marc_mod_template,
        matcher_id                           => $matcher_id,
        match_action                         => $match_action,
        matchers                             => \@matchers,
        saved                                => $saved,
    );

    $self->output_html( $template->output() );
}

sub _configure {
    my ( $self, $args ) = @_;

    my $cgi       = $self->{cgi};
    my $api_key   = $cgi->param('api_key');
    my $vendor_id = $cgi->param('vendor_id');
    my $patron_id = $cgi->param('patron_id');
    my $not_loan  = $cgi->param('not_loan');

    my $lpm_sort1                            = $cgi->param('lpm_sort1')                            // q{};
    my $lpm_sort2                            = $cgi->param('lpm_sort2')                            // q{};
    my $upm_sort1                            = $cgi->param('upm_sort1')                            // q{};
    my $upm_sort2                            = $cgi->param('upm_sort2')                            // q{};
    my $lps_sort1                            = $cgi->param('lps_sort1')                            // q{};
    my $lps_sort2                            = $cgi->param('lps_sort2')                            // q{};
    my $ups_sort1                            = $cgi->param('ups_sort1')                            // q{};
    my $ups_sort2                            = $cgi->param('ups_sort2')                            // q{};
    my $lem_sort1                            = $cgi->param('lem_sort1')                            // q{};
    my $lem_sort2                            = $cgi->param('lem_sort2')                            // q{};
    my $les_sort1                            = $cgi->param('les_sort1')                            // q{};
    my $les_sort2                            = $cgi->param('les_sort2')                            // q{};
    my $marc_mod_template                    = $cgi->param('marc_mod_template')                    // q{};
    my $create_item_for_electronic_resources = $cgi->param('create_item_for_electronic_resources') // 0;
    my $add_nonpublic_item_notes             = $cgi->param('add_nonpublic_item_notes')             // 0;
    my $matcher_id                           = $cgi->param('matcher_id')                           // q{};
    my $match_action                         = $cgi->param('match_action')                         // 'create';

    # Store new API key
    $self->store_data( { 'api_key'                              => $api_key } );
    $self->store_data( { 'vendor_id'                            => $vendor_id } );
    $self->store_data( { 'patron_id'                            => $patron_id } );
    $self->store_data( { 'not_loan'                             => $not_loan } );
    $self->store_data( { 'lpm_sort1'                            => $lpm_sort1 } );
    $self->store_data( { 'lpm_sort2'                            => $lpm_sort2 } );
    $self->store_data( { 'upm_sort1'                            => $upm_sort1 } );
    $self->store_data( { 'upm_sort2'                            => $upm_sort2 } );
    $self->store_data( { 'lps_sort1'                            => $lps_sort1 } );
    $self->store_data( { 'lps_sort2'                            => $lps_sort2 } );
    $self->store_data( { 'ups_sort1'                            => $ups_sort1 } );
    $self->store_data( { 'ups_sort2'                            => $ups_sort2 } );
    $self->store_data( { 'lem_sort1'                            => $lem_sort1 } );
    $self->store_data( { 'lem_sort2'                            => $lem_sort2 } );
    $self->store_data( { 'les_sort1'                            => $les_sort1 } );
    $self->store_data( { 'les_sort2'                            => $les_sort2 } );
    $self->store_data( { 'create_item_for_electronic_resources' => $create_item_for_electronic_resources } );
    $self->store_data( { 'add_nonpublic_item_notes'             => $add_nonpublic_item_notes } );
    $self->store_data( { marc_mod_template                      => $marc_mod_template } );
    $self->store_data( { 'matcher_id'                           => $matcher_id } );
    $self->store_data( { 'match_action'                         => $match_action } );

    $self->configure( { saved => 1 } );
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
    my $value    = $self->retrieve_data($variable) // q{};

    return $value;
}

sub install {
    my ( $self, $args ) = @_;

    my $po_table = $self->get_qualified_table_name('purchase_orders');

    C4::Context->dbh->do(
        qq{
        CREATE TABLE $po_table (
          `id` INT(11) NOT NULL auto_increment,
          `status` TEXT,
          `basketno` INT(11) REFERENCES aqbasket( basketno),
          `biblionumber` INT(11) DEFAULT NULL,
          `record_action` ENUM('created','overlayed','reused') DEFAULT NULL,
          `order_key` VARCHAR(255) DEFAULT NULL,
          `raw_msg` MEDIUMTEXT,
          `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY  (id),
          KEY basketno ( basketno),
          CONSTRAINT gobipo_basketno FOREIGN KEY ( basketno ) REFERENCES aqbasket ( basketno ) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    }
    ) unless C4::Installer::TableExists($po_table);

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $database_version = $self->retrieve_data('__INSTALLED_VERSION__') || 0;

    if ( $self->_version_compare( $database_version, "1.3.0" ) == -1 ) {

        my $po_table = $self->get_qualified_table_name('purchase_orders');

        C4::Context->dbh->do(
            qq{
            ALTER TABLE $po_table
                ADD COLUMN `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                AFTER `raw_msg`;
        }
        );

        $self->store_data( { '__INSTALLED_VERSION__' => "1.3.0" } );
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

    if ( $self->_version_compare( $database_version, "4.0.0" ) == -1 ) {

        my $po_table = $self->get_qualified_table_name('purchase_orders');

        C4::Context->dbh->do(
            qq{
            ALTER TABLE $po_table
                ADD COLUMN `biblionumber` INT(11) DEFAULT NULL AFTER `basketno`,
                ADD COLUMN `record_action` ENUM('created','overlayed','reused') DEFAULT NULL AFTER `biblionumber`;
        }
        );

        # Default to current behavior
        $self->store_data( { 'match_action' => 'create' } );

        $self->store_data( { '__INSTALLED_VERSION__' => "4.0.0" } );
    }

    if ( $self->_version_compare( $database_version, "4.0.1" ) == -1 ) {

        my $po_table = $self->get_qualified_table_name('purchase_orders');

        C4::Context->dbh->do(
            qq{
            ALTER TABLE $po_table
                ADD COLUMN `order_key` VARCHAR(255) DEFAULT NULL AFTER `record_action`;
        }
        );

        $self->store_data( { '__INSTALLED_VERSION__' => "4.0.1" } );
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

=head3 template_include_paths

Plugin hook used to register paths to find templates

=cut

sub template_include_paths {
    my ($self) = @_;

    return [
        $self->mbf_path('templates'),
    ];
}
=head2 Internal methods

=head3 set_managing_library

    $plugin->set_managing_library(
        {
            basket_id           => $basket_id,
            managing_library_id => $managing_library_id,
        }
    );

Links the I<$basket_id> to a I<$managing_library_id>. Warns if the library
is not found.

=cut

sub set_managing_library {
    my ( $self, $params ) = @_;

    $self->validate_params(
        {
            required => [qw(basket_id managing_library_id)],
            params   => $params,
        }
    );

    # Attempt to set the managing library
    try {
        $self->check_library_code( $params->{managing_library_id} );
        ModBasket(
            {
                basketno => $params->{basket_id},
                branch   => $params->{managing_library_id},
            }
        );
    } catch {
        $self->gobi_warn( sprintf( "Could not link to managing library '%s': %s", $params->{managing_library}, $_ ) );
    };

    return $self;
}

=head3 gobi_warn

    $self->gobi_warn($string);

Prints the passed string to STDERR with an identifiable label for GOBI.

=cut

sub gobi_warn {
    my ( $self, $string ) = @_;
    print STDERR sprintf( "[GOBI] %s", $string // '<empty>' );
}

=head3 validate_params

    $self->validate_params( { required => $required, params => $params } );

Reusable method for validating the passed parameters with a list of
required params.

=cut

sub validate_params {
    my ( $self, $args ) = @_;

    foreach my $param ( @{ $args->{required} } ) {
        GOBI::Exception::MissingParameter->throw( parameter => $param )
            unless exists $args->{params}->{$param};
    }

    return;
}

=head2 check_library_code

    my $library_id = $plugin->check_library_code($library_code);

Checks if the passed library code is valid. Throws I<GOBI::Exception>
if it isn't.

=cut

sub check_library_code {
    my ( $self, $library_id ) = @_;

    GOBI::Exception::MissingParameter->throw( parameter => 'library_id' )
        unless $library_id;

    GOBI::Exception::InvalidLibrary->throw( library_id => $library_id )
        unless Koha::Libraries->find($library_id);

    return $library_id;
}

=head2 check_item_type

    my $item_type = $plugin->check_item_type($item_ype);

Checks if the passed I<$item_type> is valid. Throws I<GOBI::Exception::InvalidItemType>
if it isn't.

=cut

sub check_item_type {
    my ( $self, $item_type ) = @_;

    GOBI::Exception::MissingParameter->throw( parameter => 'item_type' )
        unless $item_type;

    GOBI::Exception::InvalidItemType->throw( item_type => $item_type )
        unless Koha::ItemTypes->find($item_type);

    return $item_type;
}

=head2 check_currency

    my $currency = $plugin->check_currency($currency);

Checks if the passed I<$item_type> is valid. Throws I<GOBI::Exception::InvalidItemType>
if it isn't.

=cut

sub check_currency {
    my ( $self, $currency ) = @_;

    GOBI::Exception::MissingParameter->throw( parameter => 'currency' )
        unless $currency;

    GOBI::Exception::InvalidCurrency->throw( currency => $currency )
        unless Koha::Acquisition::Currencies->find($currency);

    return $currency;
}

=head2 check_fund_code

    my $fund_id = $plugin->check_fund_code($fund_code);

Checks if the passed I<$fund_code> is valid. Throws I<GOBI::Exception::InvalidFundCode>
if it isn't.

=cut

sub check_fund_code {
    my ( $self, $fund_code ) = @_;

    my $schema = Koha::Database->new()->schema();

    # Check budget is active !
    my $period_rs = $schema->resultset('Aqbudgetperiod')->search( { budget_period_active => 1, } );

    # Check the fund code exists and is active
    my $budget = $schema->resultset('Aqbudget')->single(
        {
            budget_code      => $fund_code,
            budget_period_id => { -in => $period_rs->get_column('budget_period_id')->as_query },
        }
    );

    GOBI::Exception::InvalidFund->throw( fund_code => $fund_code )
        unless $budget;

    return $budget->id;
}

1;
