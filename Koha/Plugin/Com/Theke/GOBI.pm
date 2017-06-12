package Koha::Plugin::Com::Theke::GOBI;

use Modern::Perl;
use utf8;

use base qw(Koha::Plugins::Base);

use C4::Acquisition qw/NewBasket CloseBasket/;
use C4::Auth;
use C4::Biblio qw/GetMarcBiblio/;
use C4::Context;
use C4::Matcher;

use Koha::Biblios;
use Koha::Items;

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
    minimum_version => '16.1200000',
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
    elsif ( $step eq 'process_marc' ) {
        $self->_process_marc();
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
    my $gpo_id;
    try {
        # Parse the raw purchase order
        $gobi_order = Koha::Plugin::Com::Theke::GOBI::PurchaseOrder->new($purchase_order_raw);
        my $record = $gobi_order->{record};
        # Create a basket
        $basketno = C4::Acquisition::NewBasket(
             1,                                        # $booksellerid  TODO: Syspref? LocalData on GOBI message?
             $logged_user,                             # $authorisedby
             $record->title,                           # $basketname    TODO: MARC21 only?
             "GOBI order",                             # $basketnote    TODO: Define what would be useful here
             $gobi_order->{OrderDetail}->{OrderNotes}, # $basketbooksellernote
             undef,                                    # $basketcontractnumber / unneeded for now
             "CPL",                                    # $deliveryplace TODO: Should be read from the GPO
             "CPL",                                    # $billingplace  TODO: Should be read from the GPO
             $gobi_order->{standing}                   # $is_standing
        );
        # Store on the plugin table
        $gpo_id = $self->_store_order( $gobi_order, $basketno, $purchase_order_raw );
        # Add biblio | TODO: Find matchings in Zebra
        my ( $biblionumber, $match ) = $self->_add_biblio_or_find_duplicate($record);

        #C4::Acquisition::CloseBasket( $basketno );
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
        gpo_id     => $gpo_id
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

sub _process_marc {
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

sub _store_order {
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

    my $biblionumber = _check_for_existing_bib( $isbn );
    if ( !defined $biblionumber ) {
        # No match, add the record
        $biblionumber = AddBiblio($record,'');
        $match = 0;
    }
    else {
        $match = 1;
    }

    return ( $biblionumber, $match );
}

sub _check_for_existing_bib {
    my $isbn = shift;

    my $search_isbn = $isbn;
    $search_isbn =~ s/^\s*/%/xms;
    $search_isbn =~ s/\s*$/%/xms;
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare(
'select biblionumber, biblioitemnumber from biblioitems where isbn like ?',
    );
    my $tuple_arr =
      $dbh->selectall_arrayref( $sth, { Slice => {} }, $search_isbn );
    if ( @{$tuple_arr} ) {
        return $tuple_arr->[0];
    }
    elsif ( length($isbn) == 13 && $isbn !~ /^97[89]/ ) {
        my $tarr = $dbh->selectall_arrayref(
'select biblionumber, biblioitemnumber from biblioitems where ean = ?',
            { Slice => {} },
            $isbn
        );
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
            $tuple_arr =
              $dbh->selectall_arrayref( $sth, { Slice => {} }, $search_isbn );
            if ( @{$tuple_arr} ) {
                return $tuple_arr->[0];
            }
        }
    }
    return;
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

    my $table = $self->get_qualified_table_name('purchase_orders');

    return C4::Context->dbh->do(
        q{
        CREATE TABLE `$table` (
          `id` INT(11) NOT NULL auto_increment,
          `status` TEXT,
          `basketno` INT(11) REFERENCES aqbasket( basketno),
          `raw_msg` MEDIUMTEXT,
          PRIMARY KEY  (id),
          KEY basketno ( basketno),
          CONSTRAINT gobipo_basketno FOREIGN KEY ( basketno ) REFERENCES aqbasket ( basketno ) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    }
    );
}

sub uninstall {
    my ( $self, $args ) = @_;

    return 1;
}



1;
