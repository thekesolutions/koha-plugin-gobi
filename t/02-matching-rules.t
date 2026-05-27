#!/usr/bin/perl

# This file is part of the Gobi plugin
#
# The Gobi plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The Gobi plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Gobi plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Test::More tests => 4;
use Test::MockModule;

use C4::Biblio qw(AddBiblio);
use C4::Context;

use Koha::Database;

use MARC::Record;

my $schema = Koha::Database->new->schema;

# Helper: build a GOBI-like MARC record with ISBN and OCLC
sub _build_record {
    my (%args) = @_;
    my $record = MARC::Record->new();
    $record->leader('00000nam a2200000u  4500');
    my @fields;
    push @fields, MARC::Field->new( '020', ' ', ' ', a => $args{isbn} ) if $args{isbn};
    push @fields, MARC::Field->new( '035', ' ', ' ', a => $args{oclc} ) if $args{oclc};
    push @fields, MARC::Field->new( '245', '1', '0', a => $args{title} // 'Test record' );
    push @fields, MARC::Field->new( '942', ' ', ' ', c => 'BK' );
    $record->append_fields(@fields);
    return $record;
}

subtest 'ISBN match triggers overlay' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    # Pre-existing record
    my $existing = _build_record( isbn => '9780809330775', title => 'Existing' );
    my ($existing_bn) = AddBiblio( $existing, '' );

    # Mock the matcher to return our existing record
    my $matcher_mock = Test::MockModule->new('C4::Matcher');
    $matcher_mock->mock( 'fetch', sub { return bless { id => 1 }, 'C4::Matcher' } );
    $matcher_mock->mock(
        'get_matches',
        sub {
            return ( { record_id => $existing_bn, score => 1000 } );
        }
    );

    # Mock plugin data retrieval
    my $plugin_mock = Test::MockModule->new('Koha::Plugin::Com::Theke::GOBI');
    $plugin_mock->mock( 'retrieve_data', sub {
        my ( $self, $key ) = @_;
        return 1             if $key eq 'matcher_id';
        return 'overlay'     if $key eq 'match_action';
        return undef;
    });

    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;

    # Build incoming GOBI order object with same ISBN
    my $incoming = _build_record( isbn => '9780809330775', title => 'GOBI Incoming' );
    my $gobi_order = bless { record => $incoming, item_type => 'BK', is_electronic => 0 }, 'Koha::Plugin::Com::Theke::GOBI::PurchaseOrder';

    my ( $biblionumber, $biblioitemnumber, $record_action ) = $plugin->_add_biblio($gobi_order);

    is( $biblionumber,  $existing_bn, 'Matched existing record by ISBN' );
    is( $record_action, 'overlayed',  'Record action is overlay' );

    $schema->storage->txn_rollback;
};

subtest 'OCLC match triggers use_existing' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    # Pre-existing record
    my $existing = _build_record( oclc => '(OCoLC)721888232', title => 'Existing OCLC' );
    my ($existing_bn) = AddBiblio( $existing, '' );

    # Mock the matcher
    my $matcher_mock = Test::MockModule->new('C4::Matcher');
    $matcher_mock->mock( 'fetch', sub { return bless { id => 1 }, 'C4::Matcher' } );
    $matcher_mock->mock(
        'get_matches',
        sub {
            return ( { record_id => $existing_bn, score => 1000 } );
        }
    );

    my $plugin_mock = Test::MockModule->new('Koha::Plugin::Com::Theke::GOBI');
    $plugin_mock->mock( 'retrieve_data', sub {
        my ( $self, $key ) = @_;
        return 1              if $key eq 'matcher_id';
        return 'use_existing' if $key eq 'match_action';
        return undef;
    });

    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;

    my $incoming = _build_record( oclc => '(OCoLC)721888232', title => 'GOBI OCLC Incoming' );
    my $gobi_order = bless { record => $incoming, item_type => 'BK', is_electronic => 0 }, 'Koha::Plugin::Com::Theke::GOBI::PurchaseOrder';

    my ( $biblionumber, $biblioitemnumber, $record_action ) = $plugin->_add_biblio($gobi_order);

    is( $biblionumber,  $existing_bn, 'Matched existing record by OCLC' );
    is( $record_action, 'reused',     'Record action is reused' );

    $schema->storage->txn_rollback;
};

subtest 'No match creates new record' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    # Mock matcher returning no matches
    my $matcher_mock = Test::MockModule->new('C4::Matcher');
    $matcher_mock->mock( 'fetch', sub { return bless { id => 1 }, 'C4::Matcher' } );
    $matcher_mock->mock( 'get_matches', sub { return () } );

    my $plugin_mock = Test::MockModule->new('Koha::Plugin::Com::Theke::GOBI');
    $plugin_mock->mock( 'retrieve_data', sub {
        my ( $self, $key ) = @_;
        return 1              if $key eq 'matcher_id';
        return 'use_existing' if $key eq 'match_action';
        return undef;
    });

    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;

    my $incoming = _build_record( isbn => '9781234567890', title => 'Brand new book' );
    my $gobi_order = bless { record => $incoming, item_type => 'BK', is_electronic => 0 }, 'Koha::Plugin::Com::Theke::GOBI::PurchaseOrder';

    my ( $biblionumber, $biblioitemnumber, $record_action ) = $plugin->_add_biblio($gobi_order);

    ok( $biblionumber, 'New biblionumber created when no match' );
    is( $record_action, 'created', 'Record action is created' );

    $schema->storage->txn_rollback;
};

subtest 'No matcher configured creates new record' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    # No matcher configured
    my $plugin_mock = Test::MockModule->new('Koha::Plugin::Com::Theke::GOBI');
    $plugin_mock->mock( 'retrieve_data', sub {
        my ( $self, $key ) = @_;
        return undef if $key eq 'matcher_id';
        return undef;
    });

    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;

    my $incoming = _build_record( isbn => '9781111111111', title => 'No matcher configured' );
    my $gobi_order = bless { record => $incoming, item_type => 'BK', is_electronic => 0 }, 'Koha::Plugin::Com::Theke::GOBI::PurchaseOrder';

    my ( $biblionumber, $biblioitemnumber, $record_action ) = $plugin->_add_biblio($gobi_order);

    ok( $biblionumber, 'New biblionumber created when no matcher configured' );
    is( $record_action, 'created', 'Record action is created' );

    $schema->storage->txn_rollback;
};
