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

use Test::More tests => 8;
use Test::MockModule;

use Koha::Database;

my $schema = Koha::Database->new->schema;
$schema->storage->txn_begin;

use_ok('Koha::Plugin::Com::Theke::GOBI');

subtest 'Plugin instantiation' => sub {
    plan tests => 2;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    ok( $plugin, 'Plugin instantiated successfully' );
    isa_ok( $plugin, 'Koha::Plugin::Com::Theke::GOBI', 'Plugin is correct class' );
};

subtest 'Plugin metadata' => sub {
    plan tests => 4;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    ok( $plugin->get_metadata->{name}, 'Plugin has name' );
    ok( $plugin->get_metadata->{version}, 'Plugin has version' );
    ok( $plugin->get_metadata->{description}, 'Plugin has description' );
    ok( $plugin->get_metadata->{author}, 'Plugin has author' );
};

subtest 'Plugin methods' => sub {
    plan tests => 4;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    can_ok( $plugin, 'new' );
    can_ok( $plugin, 'install' );
    can_ok( $plugin, 'upgrade' );
    can_ok( $plugin, 'uninstall' );
};

subtest 'Configuration methods' => sub {
    plan tests => 2;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    can_ok( $plugin, 'configure' );
    can_ok( $plugin, 'tool' );
};

subtest 'API methods' => sub {
    plan tests => 2;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    can_ok( $plugin, 'api_routes' );
    can_ok( $plugin, 'api_namespace' );
};

subtest 'Hook methods' => sub {
    plan tests => 1;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    # Check if plugin has any hook methods
    # This will depend on what hooks the Gobi plugin actually implements
    ok( 1, 'Hook methods check placeholder' );
};

subtest 'Plugin functionality' => sub {
    plan tests => 1;
    
    my $plugin = Koha::Plugin::Com::Theke::GOBI->new;
    
    # Basic functionality test
    # This should be expanded based on actual Gobi plugin features
    ok( 1, 'Basic functionality test placeholder' );
};

$schema->storage->txn_rollback;
