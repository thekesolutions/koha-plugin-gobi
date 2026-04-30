package Koha::Plugin::Com::Theke::GOBI::Controller;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Koha::Plugin::Com::Theke::GOBI;
use Koha::Plugin::Com::Theke::GOBI::Exception;
use GOBI::Orders;

use Mojo::Base 'Mojolicious::Controller';

use Try::Tiny;

# Register the plugin's DBIC Result class with Koha's schema
Koha::Database->new->schema->register_class(
    KohaPluginComThekeGobiPurchaseOrder =>
        'Koha::Schema::Result::KohaPluginComThekeGobiPurchaseOrder'
);

=head1 Koha::Plugin::Com::Theke::GOBI::Controller

A class implementing the controller code for GOBI requests

=head2 Class methods

=head3 list_orders

Lists GOBI purchase orders with server-side pagination, filtering, and sorting.

=cut

sub list_orders {
    my $c = shift->openapi->valid_input or return;

    return try {
        return $c->render(
            status  => 200,
            openapi => $c->objects->search( GOBI::Orders->new ),
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 list_order_filters

Returns distinct values for filterable columns (status, record_action).

=cut

sub list_order_filters {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $rs = GOBI::Orders->new->_resultset;

        my @statuses       = map { $_->get_column('status') }        $rs->search( undef, { columns => ['status'],        distinct => 1 } )->all;
        my @record_actions = map { $_->get_column('record_action') } $rs->search( { record_action => { '!=' => undef } }, { columns => ['record_action'], distinct => 1 } )->all;

        return $c->render(
            status  => 200,
            openapi => {
                statuses       => \@statuses,
                record_actions => \@record_actions,
            },
        );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 marc_preview

Returns formatted MARC for a GOBI order: the incoming record from the
raw XML, and the current catalog record if one was linked.

=cut

sub marc_preview {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $id    = $c->param('gobi_order_id');
        my $order = GOBI::Orders->new->find($id);

        return $c->render( status => 404, openapi => { error => 'Order not found' } )
            unless $order;

        my $result = { gobi_order_id => $id, record_action => $order->record_action };

        # Parse incoming MARC from raw XML
        if ( $order->raw_msg ) {
            require MARC::Record;
            require MARC::File::XML;
            my $xml = $order->raw_msg;
            if ( $xml =~ m{(<record.*?</record>)}s ) {
                my $incoming = eval { MARC::Record::new_from_xml( "<collection>$1</collection>", 'UTF-8' ) };
                $result->{incoming_marc} = $incoming->as_formatted if $incoming;
            }
        }

        # Fetch current catalog record if linked
        if ( $order->biblionumber ) {
            my $biblio = Koha::Biblios->find( $order->biblionumber );
            if ($biblio) {
                my $catalog_record = $biblio->metadata->record;
                $result->{catalog_marc} = $catalog_record->as_formatted if $catalog_record;
                $result->{biblio_id}    = $order->biblionumber;
            }
        }

        return $c->render( status => 200, openapi => $result );
    } catch {
        return $c->unhandled_exception($_);
    };
}

=head3 add_order

Method that adds a new order from a GOBI request

=cut

sub add_order {
    my $c = shift->openapi->valid_input or return;

    my $api_key = $c->param('api_key');
    my $plugin  = Koha::Plugin::Com::Theke::GOBI->new;

    # Check API key is present
    if ( !defined $api_key ) {
        $c->render(
            status => 400,
            text   => $c->render_response(
                {
                    error   => 1,
                    code    => 'API_KEY_MISSING',
                    message => "API Key parameter missing on request."
                }
            )
        );
    }

    # Check API key is valid
    if ( !$plugin->api_key_valid($api_key) ) {
        $c->render(
            status => 403,
            text   => $c->render_response(
                {
                    error   => 1,
                    code    => 'API_KEY_INVALID',
                    message => "The API Key \"$api_key\" is an invalid."
                }
            )
        );
    } else {

        # Ok, passed, moving on!
        my $body = $c->req->body;

        if ( !defined $body ) {

            $plugin->gobi_warn("ORDER_DATA_MISSING: Purchase Order XML data is missing in POST");

            $c->render(
                status => 400,
                text   => $c->render_response(
                    {
                        error   => 1,
                        code    => 'ORDER_DATA_MISSING',
                        message => "Purchase Order XML data is missing in POST."
                    }
                )
            );
        }

        return try {
            my $order_id = $plugin->add_order($body);
            unless ($order_id) {
                GOBI::Exception->throw('No order generated.');
            }
            $c->render(
                status => 200,
                text   => $c->render_response( { order_id => $order_id } )
            );
        } catch {

            $plugin->gobi_warn( sprintf( "REQUEST_PROCESSING_ERROR: %s", $_ ) );

            return $c->render(
                status => 400,
                text   => $c->render_response(
                    {
                        error   => 1,
                        code    => 'REQUEST_PROCESSING_ERROR',
                        message => "$_"
                    }
                )
            );
        };
    }
}

=head2 Internal methods

=head3 render_response

Internal method that generates the XML string representing a response

=cut

sub render_response {
    my ( $c, $args ) = @_;

    my $code     = $args->{code}    // '';
    my $message  = $args->{message} // '';
    my $order_id = $args->{order_id};

    unless ( $order_id or ( $code and $message ) ) {
        GOBI::Exception->throw('Bad parameters for render_response.');
    }

    my $xml;

    if ( $args->{error} ) {
        $xml = qq{<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Error>
        <Code>$code</Code>
        <Message>$message</Message>
    </Error>
</Response>};
    } else {
        $xml = qq{<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <PoLineNumber>$order_id</PoLineNumber>
</Response>};
    }

    return $xml;
}

1;
