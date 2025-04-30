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

use Mojo::Base 'Mojolicious::Controller';

use Try::Tiny;

=head1 Koha::Plugin::Com::Theke::GOBI::Controller

A class implementing the controller code for GOBI requests

=head2 Class methods

=head3 add_order

Method that adds a new order from a GOBI request

=cut

sub add_order {
    my $c = shift->openapi->valid_input or return;

    my $api_key = $c->param('api_key');
    my $gobi = Koha::Plugin::Com::Theke::GOBI->new;

    # Check API key is present
    if ( !defined $api_key ) {
        $c->render(
            status => 400,
            text   => $c->render_response({
                error   => 1,
                code    => 'API_KEY_MISSING',
                message => "API Key parameter missing on request."
            })
        );
    }

    # Check API key is valid
    if ( !$gobi->api_key_valid($api_key) ) {
        $c->render(
            status => 403,
            text   => $c->render_response({
                error   => 1,
                code    => 'API_KEY_INVALID',
                message => "The API Key \"$api_key\" is an invalid."
            })
        );
    }else {

        # Ok, passed, moving on!
        my $body = $c->req->body;

        if ( !defined $body ) {

            warn "ORDER_DATA_MISSING: Purchase Order XML data is missing in POST.";

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
            my $order_id = $gobi->add_order($body);
            unless ($order_id) {
                GOBI::Exception->throw('No order generated.');
            }
            $c->render(
                status => 200,
                text   => $c->render_response({ order_id => $order_id })
            );
        }
        catch {

            warn "REQUEST_PROCESSING_ERROR: $_";

            return $c->render(
                status => 400,
                text   => $c->render_response({
                    error   => 1,
                    code    => 'REQUEST_PROCESSING_ERROR',
                    message => "$_"
                })
            );
        };
    }
}

=head2 Internal methods

=head3 render_response

Internal method that generates the XML string representing a response

=cut

sub render_response {
    my ($c, $args) = @_;

    my $code     = $args->{code} // '';
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
    }
    else {
        $xml = qq{<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <PoLineNumber>$order_id</PoLineNumber>
</Response>};
    }

    return $xml;
}

1;
