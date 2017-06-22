package Koha::Plugin::Com::Theke::GOBI;

use Modern::Perl;
use utf8;

use base qw(Koha::Plugins::Base);

use C4::Acquisition qw/NewBasket CloseBasket/;
use C4::Auth;
use C4::Biblio qw/AddBiblio GetMarcBiblio/;
use C4::Items qw/AddItem/;
use C4::Context;
use C4::Matcher;

use Koha::Acquisition::Booksellers;
use Koha::Biblios;
use Koha::Acquisition::Currencies;
use Koha::Items;
use Koha::Libraries;
use Koha::Number::Price;

use Koha::Plugin::Com::Theke::GOBI::PurchaseOrder;

use Data::Printer;
use Try::Tiny;

use MARC::Record;

our $VERSION = 0.1;

our $metadata = {
    name            => 'GOBI integration',
    author          => 'BWS',
    description     => 'Integrates GOBI with Koha',
    date_authored   => '2017-05-10',
    date_updated    => '2017-05-10',
    minimum_version => '17.0500000',
    maximum_version => undef,
    version         => $VERSION,
};

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
        $self->configure();
    }
    else {
        # $step eq 'render'
        $self->_list_orders();
    }
}

sub _add_order {
    my ( $self, $args ) = @_;

    my $cgi                = $self->{cgi};
    my $purchase_order_raw = $cgi->param('purchase-order-xml');
    my $template           = $self->get_template( { file => 'order_details.tt' } );

    my $logged_user = C4::Auth::getborrowernumber();
    my $basketno;
    my $gobi_order;
    my $gobi_order_id;

    my @itemnumbers;

    my $schema = Koha::Database->new()->schema();
    $schema->storage->txn_begin();

    try {
        # Parse the raw purchase order
        $gobi_order = Koha::Plugin::Com::Theke::GOBI::PurchaseOrder->new($purchase_order_raw);
        my $record = $gobi_order->{record};
        my $quantity = $gobi_order->OrderDetail->{Quantity} // 0;

        # Some basic checks for data health
        my $fund_id      = $self->_check_fund_code($gobi_order);
        my $library_code = $self->_check_library_code($gobi_order);
        my $vendor_code  = $self->_check_vendor_code($gobi_order);
        my $currency     = $self->_check_currency($gobi_order);
        my $price        = $gobi_order->OrderDetail->{ListPriceAmount} // 0;
        my $location     = $gobi_order->OrderDetail->{Location} // q{};        # no fk

        # Create a basket
        $basketno = C4::Acquisition::NewBasket(
            $vendor_code
            ,    # $booksellerid  TODO: Discuss syspref/config vs. LocalData on GOBI message
            $logged_user,              # $authorisedby
            $record->title,            # $basketname    TODO: MARC21 only?
            "GOBI order",              # $basketnote    TODO: Define what would be useful here
            q{},                       # $basketbooksellernote
            undef,                     # $basketcontractnumber / unneeded for now
            $library_code,
            $library_code,
            $gobi_order->{standing}    # $is_standing
        );

        # Store on the plugin table TODO: Figure what we would really need
        $gobi_order_id = $self->_store_gobi_order( $gobi_order, $basketno, $purchase_order_raw );

        # Add biblio
        my ( $biblionumber, $match ) = $self->_add_biblio_or_find_duplicate($record);

        my $order_data = {
            biblionumber               => $biblionumber,
            basketno                   => $basketno,
            budget_id                  => $fund_id,
            listprice                  => $price,
            quantity                   => $quantity,
            quantityreceived           => 0,
            order_vendornote           => $gobi_order->OrderDetail->{OrderNotes},
            order_internalnote         => q{},
            sort1                      => q{},
            sort2                      => q{},
            currency                   => $currency,
            suppliers_reference_number => $gobi_order->OrderDetail->{YBPOrderKey}
        };
        $order_data = $self->_add_price_data( $vendor_code, $price, $quantity, $order_data );
        my $koha_order = Koha::Acquisition::Order->new($order_data)->insert;

        # Are we configured to generate items on ordering?
        if ( C4::Context->preference('AcqCreateItem') eq 'ordering'
            && $quantity > 0 )
        {
            for ( my $i = 0; $i < $quantity; $i++ ) {
                my $item_data
                    = $self->_generate_item_data( $gobi_order, $vendor_code, $price, $library_code,
                    $location );
                my ( undef, undef, $itemnumber ) = AddItem( $item_data, $biblionumber );
                push @itemnumbers, $itemnumber;
            }
            $koha_order->add_item($_) for @itemnumbers;
        }

        #C4::Acquisition::CloseBasket( $basketno );
    }
    catch {
        # Problem found, rollback transaction, notify error
        $schema->storage->txn_rollback();
        if ( $_->isa('GOBI::Exception') ) {
            $template->param( error => $_->error );
        }
        else {
            $template->param( error => $_ );
        }
    };

    $template->param(
        gobi_order    => $gobi_order,
        gobi_order_id => $gobi_order_id
    );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
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

    $template->param( gobi_orders => $gobi_orders );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
}

sub _store_gobi_order {
    my ( $self, $gobi_order, $basketno, $raw ) = @_;

    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        INSERT INTO $table
               ( itemponumber, status, basketno, raw_msg )
        VALUES ( ?,            ?,      ?,        ? )
    " );

    $sth->execute( $gobi_order->{OrderDetail}->{ItemPONumber}, 'processed', $basketno, $raw );

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

sub _add_biblio_or_find_duplicate {

    my ( $self, $record ) = @_;

    # TODO: GOBI passes MARC21 records. Maybe prepare for future changes
    my $isbn = $record->subfield( '020', 'a' );
    my $match;

    my $biblionumber = _check_for_existing_bib($isbn);
    if ( !defined $biblionumber ) {

        # No match, add the record
        ( $biblionumber, undef ) = AddBiblio( $record, '' );
        $match = 0;
    }
    else {
        $match = 1;
    }

    return ( $biblionumber, $match );
}

sub _generate_item_data {
    my ( $self, $gobi_order, $vendor_code, $price, $library, $location ) = @_;

    my $item_data = {
        booksellerid     => $vendor_code,
        cn_source        => C4::Context->preference('DefaultClassificationSource'),
        cn_sort          => q{},
        holdingbranch    => $library,
        homebranch       => $library,
        location         => $location,
        notforloan       => -1,
        price            => $price,
        replacementprice => $price
    };

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
    my $discount = $bookseller->discount / 100;

    $order_data->{tax_rate} = $tax_rate;
    $order_data->{discount} = $discount;

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

sub _check_for_existing_bib {
    my $isbn = shift;

    my $search_isbn = $isbn;
    $search_isbn =~ s/^\s*/%/xms;
    $search_isbn =~ s/\s*$/%/xms;
    my $dbh       = C4::Context->dbh;
    my $sth       = $dbh->prepare( 'SELECT biblionumber FROM biblioitems WHERE isbn LIKE ?' );
    my $tuple_arr = $dbh->selectall_arrayref( $sth, { Slice => {} }, $search_isbn );
    if ( @{$tuple_arr} ) {
        return $tuple_arr->[0];
    }
    elsif ( length($isbn) == 13 && $isbn !~ /^97[89]/ ) {
        my $tarr = $dbh->selectall_arrayref( 'SELECT biblionumber FROM biblioitems WHERE ean = ?',
            { Slice => {} }, $isbn );
        if ( @{$tarr} ) {
            return $tarr->[0];
        }
    }
    else {
        undef $search_isbn;
        $isbn =~ s/\-//xmsg;
        if ( $isbn =~ m/(\d{13})/xms ) {
            my $b_isbn = Business::ISBN->new($1);
            if ( $b_isbn && $b_isbn->is_valid ) {
                $search_isbn = $b_isbn->as_isbn10->as_string( [] );
            }

        }
        elsif ( $isbn =~ m/(\d{9}[xX]|\d{10})/xms ) {
            my $b_isbn = Business::ISBN->new($1);
            if ( $b_isbn && $b_isbn->is_valid ) {
                $search_isbn = $b_isbn->as_isbn13->as_string( [] );
            }

        }
        if ($search_isbn) {
            $search_isbn = "%$search_isbn%";
            $tuple_arr = $dbh->selectall_arrayref( $sth, { Slice => {} }, $search_isbn );
            if ( @{$tuple_arr} ) {
                return $tuple_arr->[0];
            }
        }
    }
    return;
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
    my $library_code = $gobi_order->OrderDetail->{LocalData}->{Library};

    if ( !defined $library_code ) {
        GOBI::Exception->throw("Missing library code.");
    }

    GOBI::Exception->throw("Invalid library code passed ($library_code)")
        unless Koha::Libraries->find($library_code);

    return $library_code;
}

sub _check_vendor_code {
    my ( $self, $gobi_order ) = @_;

    # We actually call it fund
    my $vendor_code = $gobi_order->OrderDetail->{LocalData}->{VendorCode};

    if ( !defined $vendor_code ) {
        GOBI::Exception->throw("Missing vendor code.");
    }

    GOBI::Exception->throw("Invalid vendor code passed ($vendor_code)")
        unless Koha::Acquisition::Booksellers->find($vendor_code);

    return $vendor_code;
}

sub _check_currency {
    my ( $self, $gobi_order ) = @_;

    # We actually call it fund
    my $currency = $gobi_order->OrderDetail->{ListPriceCurrency};

    if ( !defined $currency ) {
        GOBI::Exception->throw("Missing currency code.");
    }

    GOBI::Exception->throw("Invalid vendor code passed ($currency)")
        unless Koha::Acquisition::Currencies->find($currency);

    return $currency;
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

sub install {
    my ( $self, $args ) = @_;

    my $po_table   = $self->get_qualified_table_name('purchase_orders');
    my $conf_table = $self->get_qualified_table_name('configuration');

    C4::Context->dbh->do(q{
        CREATE TABLE `$po_table` (
          `id` INT(11) NOT NULL auto_increment,
          `status` TEXT,
          `basketno` INT(11) REFERENCES aqbasket( basketno),
          `raw_msg` MEDIUMTEXT,
          PRIMARY KEY  (id),
          KEY basketno ( basketno),
          CONSTRAINT gobipo_basketno FOREIGN KEY ( basketno ) REFERENCES aqbasket ( basketno ) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    }) unless $self->_table_exists($po_table);

    C4::Context->dbh->do(q{
        CREATE TABLE `$conf_table` (
          `variable` varchar(50) NOT NULL default '',
          `value` text,
          PRIMARY KEY  (`variable`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    }) unless $self->_table_exists($conf_table);

    return 1;
}

sub configure {
    my ( $self, $args ) = @_;

    #my $table = $self->get_qualified_table_name('configuration');

    my $cgi = $self->{cgi};

    my $template = $self->get_template( { file => 'main.tt' } );

    # Fetch from DB marching a criteria
    my $table = $self->get_qualified_table_name('purchase_orders');
    my $sth   = C4::Context->dbh->prepare( "
        SELECT * FROM $table
    " );

    $sth->execute();
    my $gobi_orders = $sth->fetchall_arrayref( {} );

    $template->param( gobi_orders => $gobi_orders );

    print $cgi->header( -charset => 'utf-8' );
    print $template->output();
}

sub uninstall {
    my ( $self, $args ) = @_;

    return 1;
}

1;
