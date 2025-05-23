package Koha::Plugin::Com::Theke::GOBI::Exception;

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

use Koha::Exceptions;

use Exception::Class (
    'GOBI::Exception' => {
        isa         => 'Koha::Exception',
        description => 'Generic GOBI exception',
    },
    'GOBI::Exception::InvalidCurrency' => {
        isa         => 'GOBI::Exception',
        description => 'The passed item type is invalid',
        fields      => ['currency']
    },
    'GOBI::Exception::InvalidFund' => {
        isa         => 'GOBI::Exception',
        description => 'The passed fund code is invalid',
        fields      => ['fund_code']
    },
    'GOBI::Exception::InvalidItemType' => {
        isa         => 'GOBI::Exception',
        description => 'The passed item type is invalid',
        fields      => ['item_type']
    },
    'GOBI::Exception::InvalidLibrary' => {
        isa         => 'GOBI::Exception',
        description => 'The passed library ID is invalid',
        fields      => ['library_id']
    },
    'GOBI::Exception::MissingParameter' => {
        isa         => 'GOBI::Exception',
        description => 'Mandatory parameter missing',
        fields      => ['parameter'],
    },
    'GOBI::Exceptions::CustomerDetailNotFound' => {
        isa         => 'GOBI::Exception',
        description => 'Mandatory CustomerDetail not found'
    },
    'GOBI::Exceptions::MissingMandatoryField' => {
        isa         => 'GOBI::Exception',
        description => 'A mandatory field is missing on the order message'
    },
    'GOBI::Exceptions::NoXML' => {
        isa         => 'GOBI::Exception',
        description => 'XML missing in constructor'
    },
    'GOBI::Exceptions::OrderDetailNotFound' => {
        isa         => 'GOBI::Exception',
        description => 'Mandatory OrderDetail not found'
    },
    'GOBI::Exceptions::DBError' => {
        isa         => 'GOBI::Exception',
        description => 'General DB error'
    }
);

1;
