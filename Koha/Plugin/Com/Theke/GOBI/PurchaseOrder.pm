package Koha::Plugin::Com::Theke::GOBI::PurchaseOrder;

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

use List::MoreUtils qw/any/;
use MARC::File::XML;
use MARC::Record;
use Try::Tiny;

use Koha::Plugin::Com::Theke::GOBI::Exception;

use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(
    qw( record standing type CustomerDetail OrderDetail item_po_number item_type shelving_location selector_notes )
);

sub new {

    my $class = shift;
    my $xml   = shift;

    if ( !defined $xml ) {
        GOBI::Exceptions::NoXML->throw( error => 'Required XML missing' );
    }

    my $result;
    try {
        $result = _read_xml($xml);
    }
    catch {
        if ( ref($_) && $_->isa('GOBI::Exception') ) {
            $_->rethrow();
        }
        else {
            GOBI::Exception->throw( error => $_ );
        }
    };

    my $self = $class->SUPER::new($result);

    bless $self, $class;
    return $self;
}

sub _read_xml {

    my $xml_string = shift;
    my $result;

    require XML::LibXML;

    my $parser = XML::LibXML->new();
    my $xml;
    try {
        $xml = $parser->load_xml( string => $xml_string );
    }
    catch {
        GOBI::Exception->throw( error => 'XML error' );
    };

    my $record_xml = @{ $xml->getElementsByTagName('record') }[0];
    my $record     = MARC::Record->new_from_xml($record_xml);
    $result->{record} = $record;

    my $order_type_xml = @{ $xml->find('//PurchaseOrder/Order/*[1]') }[0];
    $result->{type} = $order_type_xml->tagName;
    # $result->{standing}
    #     = any { $_ eq $result->{type} } qw( ListedElectronicSerial ListedPrintSerial );

    # CustomerDetail
    $result->{CustomerDetail}    = _read_customer_detail($xml);
    $result->{OrderDetail}       = _read_order_detail($xml);
    $result->{item_po_number}    = $result->{OrderDetail}->{ItemPONumber};
    $result->{item_type}         = %{@{$result->{OrderDetail}->{LocalData}}[0]}{value};
    $result->{shelving_location} = %{@{$result->{OrderDetail}->{LocalData}}[1]}{value};
    $result->{selector_notes}    = %{@{$result->{OrderDetail}->{LocalData}}[2]}{value};

    return $result;
}

sub _read_customer_detail {
    my $xml = shift;

    my $customer_detail;

    my $base_account = @{ $xml->find('//PurchaseOrder/CustomerDetail/BaseAccount') }[0];
    my $sub_account  = @{ $xml->find('//PurchaseOrder/CustomerDetail/SubAccount') }[0];

    $customer_detail->{BaseAccount} = $base_account->textContent;
    $customer_detail->{SubAccount}  = $sub_account->textContent;

    return $customer_detail;
}

sub _read_order_detail {
    my $xml = shift;

    my $order_detail;

    if ( !$xml->find('//PurchaseOrder/Order//OrderDetail') ) {
        GOBI::Exceptions::OrderDetailNotFound->throw( error => 'OrderDetail not found on request' );
    }

    my $ItemPONumber = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/ItemPONumber') }[0];
    my $FundCode     = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/FundCode') }[0];
    my $OrderNotes   = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/OrderNotes') }[0];
    my $Location     = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/Location') }[0];
    my $Quantity     = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/Quantity') }[0];
    my $YBPOrderKey  = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/YBPOrderKey') }[0];
    my $OrderPlaced  = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/OrderPlaced') }[0];
    my $Initials     = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/Initials') }[0];
    my $LocalData;

    foreach my $local_data ( @{ $xml->find('//PurchaseOrder/Order//OrderDetail/LocalData') } ) {
        push @{$LocalData},
            {
                description => @{ $local_data->find('Description') }[0]->textContent,
                value       => @{ $local_data->find('Value') }[0]->textContent
            };
    }

    $order_detail->{ItemPONumber} = $ItemPONumber->textContent
        if defined $ItemPONumber;
    $order_detail->{FundCode} = $FundCode->textContent
        if defined $FundCode;
    $order_detail->{OrderNotes} = $OrderNotes->textContent
        if defined $OrderNotes;
    $order_detail->{Location} = $Location->textContent
        if defined $Location;
    $order_detail->{Quantity} = $Quantity->textContent
        if defined $Quantity;
    $order_detail->{YBPOrderKey} = $YBPOrderKey->textContent
        if defined $YBPOrderKey;
    $order_detail->{OrderPlaced} = $OrderPlaced->textContent
        if defined $OrderPlaced;
    $order_detail->{Initials} = $Initials->textContent
        if defined $Initials;
    $order_detail->{LocalData} = $LocalData
        if defined $LocalData;

    my $ListPriceAmount = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/ListPrice/Amount') }[0];
    my $ListPriceCurrency
        = @{ $xml->find('//PurchaseOrder/Order//OrderDetail/ListPrice/Currency') }[0];

    $order_detail->{ListPriceAmount} = $ListPriceAmount->textContent
        if defined $ListPriceAmount;

    $order_detail->{ListPriceCurrency} = $ListPriceCurrency->textContent
        if defined $ListPriceCurrency;

    if ( $xml->find('/PurchaseOrder//OrderDetail/PurchaseOption') ) {
        my $VendorPOCode = @{ $xml->find('//PurchaseOrder//PurchaseOption/VendorPOCode') }[0];
        my $Code         = @{ $xml->find('//PurchaseOrder//PurchaseOption/Code') }[0];
        my $Description  = @{ $xml->find('//PurchaseOrder//PurchaseOption/Description') }[0];
        my $VendorCode   = @{ $xml->find('//PurchaseOrder//PurchaseOption/VendorCode') }[0];

        my $PurchaseOption;
        $PurchaseOption->{VendorPOCode} = $VendorPOCode->textContent
            if defined $VendorPOCode;
        $PurchaseOption->{Code} = $Code->textContent
            if defined $Code;
        $PurchaseOption->{Description} = $Description->textContent
            if defined $Description;
        $PurchaseOption->{VendorCode} = $VendorCode->textContent
            if defined $VendorCode;

        $order_detail->{PurchaseOption} = $PurchaseOption
            if defined $PurchaseOption;
    }

    return $order_detail;
}

1;
