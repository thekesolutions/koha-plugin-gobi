#!/usr/bin/perl

use Modern::Perl;

use Data::Printer colored => 1;
use File::Slurp;
use MARC::File::XML;
use MARC::Record;
use Try::Tiny;
use XML::LibXML;

use Koha::Plugin::Com::Theke::GOBI::PurchaseOrder;

use File::Basename;
my $dirname = dirname(__FILE__);

my $file = "$dirname/../sample_data/1_ListedElectronicMonograph.xml";
#my $file = 'ybp/GobiAPIRequestAndResponseExamples/6_UnlistedPrintSerial.xml';
my $xml_string = read_file($file);

my $gobi_order;
try {
    $gobi_order = Koha::Plugin::Com::Theke::GOBI::PurchaseOrder->new($xml_string);
    p($gobi_order);
}
catch {
    if ( blessed $_ && $_->isa('GOBI::Exception') ) {
        p( $_->error );
    }
    else {
        die $_;
    }
};

1;
