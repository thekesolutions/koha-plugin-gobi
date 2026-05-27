package Koha::Schema::Result::KohaPluginComThekeGobiPurchaseOrder;

use base 'DBIx::Class::Core';

__PACKAGE__->table('koha_plugin_com_theke_gobi_purchase_orders');

__PACKAGE__->add_columns(
    'id',            { data_type => 'integer', is_auto_increment => 1, is_nullable => 0 },
    'status',        { data_type => 'text',    is_nullable       => 1 },
    'basketno',      { data_type => 'integer', is_foreign_key    => 1, is_nullable => 1 },
    'biblionumber',  { data_type => 'integer', is_nullable       => 1 },
    'record_action', { data_type => 'enum',    extra => { list => [qw(created overlayed reused)] }, is_nullable => 1 },
    'order_key',     { data_type => 'varchar', size => 255, is_nullable => 1 },
    'raw_msg',       { data_type => 'mediumtext', is_nullable    => 1 },
    'timestamp',     { data_type => 'timestamp',  is_nullable    => 0 },
);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(
    'basket',
    'Koha::Schema::Result::Aqbasket',
    { 'foreign.basketno' => 'self.basketno' },
    { join_type          => 'LEFT' },
);

1;
