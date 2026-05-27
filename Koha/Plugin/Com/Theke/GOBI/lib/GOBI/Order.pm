package GOBI::Order;

# Copyright 2026 Theke Solutions
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

use Koha::Acquisition::Baskets;
use Koha::Biblios;

use base qw(Koha::Object);

=head1 NAME

GOBI::Order - Koha::Object subclass for GOBI purchase orders

=head1 API

=head2 Internal methods

=head3 _type

=cut

sub _type { return 'KohaPluginComThekeGobiPurchaseOrder' }

=head3 to_api_mapping

=cut

sub to_api_mapping {
    return {
        id           => 'gobi_order_id',
        basketno     => 'basket_id',
        biblionumber => 'biblio_id',
        order_key    => 'order_key',
    };
}

=head3 basket

=cut

sub basket {
    my ($self) = @_;
    return Koha::Acquisition::Basket->_new_from_dbic( scalar $self->_result->basket );
}

=head3 biblio

=cut

sub biblio {
    my ($self) = @_;
    my $biblio_rs = $self->_result->biblio or return;
    return Koha::Biblio->_new_from_dbic($biblio_rs);
}

1;
