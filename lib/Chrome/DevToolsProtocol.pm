package Chrome::DevToolsProtocol;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use AnyEvent;
use AnyEvent::WebSocket::Client;
use Future;
use AnyEvent::Future qw(as_future_cb);
use Future::HTTP;
use Carp qw(croak);
use JSON;
use Data::Dumper;
use Chrome::DevToolsProtocol::Extension;

use vars qw<$VERSION $magic>;
$VERSION = '0.01';
$magic = "ChromeDevToolsHandshake";

# DOM access
# https://chromedevtools.github.io/devtools-protocol/tot/DOM/
# http://localhost:9222/json

sub new($class, %args) {
    my $self = bless \%args => $class;

    # Set up defaults
    $args{ host } ||= 'localhost';
    $args{ port } ||= 9222;
    $args{ json } ||= JSON->new;
    $args{ ua } ||= Future::HTTP->new;
    $args{ sequence_number } ||= 0;

    # XXX Make receivers multi-level on Tool+Destination
    $args{ receivers } ||= {};

    $self
};

sub host( $self ) { $self->{host} }
sub port( $self ) { $self->{port} }
sub endpoint( $self ) { $self->{endpoint} }
sub json( $self ) { $self->{json} }
sub ua( $self ) { $self->{ua} }
sub ws( $self ) { $self->{ws} }

sub log( $self, $level, $message, @args ) {
    if( my $handler = $self->{log} ) {
        shift;
        goto &$handler;
    } else {
        if( !@args ) {
            warn "$level: $message";
        } else {
            warn "$level: $message " . Dumper @args;
        };
    };
}

sub connect( $self, %args ) {
    # Kick off the connect

    my $endpoint;
    if( $args{ tab }) {
        $endpoint = $args{ tab }->{webSocketDebuggerUrl};
    } else {
        $endpoint = $args{ endpoint } || $self->endpoint;
    };

    my $got_endpoint;
    if( ! $endpoint ) {

        # find the debugger endpoint:
        # These are the open tabs
        $got_endpoint = $self->list_tabs()->then(sub($tabs) {
            my $endpoint = $tabs->[0]->{webSocketDebuggerUrl};
            Future->done( $endpoint );
        });
    } else {
        $got_endpoint = Future->done( $endpoint );
    };

    my $client;
    $got_endpoint->then( sub( $endpoint ) {
        as_future_cb( sub( $done_cb, $fail_cb ) {
            $self->log('DEBUG',"Connecting to $endpoint");
            $client = AnyEvent::WebSocket::Client->new;
            $client->connect( $endpoint )->cb( $done_cb );
        });
    })->then( sub( $c ) {
        $self->log( 'DEBUG', sprintf "Connected to %s:%s", $self->host, $self->port );
        my $connection = $c->recv;

        # Well, it's a tab, not the whole Chrome process here...
        $self->{chrome} ||= $connection;

        # Kick off the continous polling
        $self->{chrome}->on( each_message => sub( $connection,$message) {
            $self->on_response( $connection, $message )
        });

        $self->{ws} = $connection;

        Future->done( $connection )
    });
};

sub on_response( $self, $connection, $message ) {
    my $response = $self->json->decode( $message->{body});
    $self->log( 'DEBUG', "Replying to $response->{id}", $response );

    if( $response->{error} ) {
        $self->{receivers}->{$response->{id}}->die(  $response->{error}->{message},$response->{error}->{code} );
    } else {
        $self->{receivers}->{$response->{id}}->done( $response->{body} );
    };
}

sub next_sequence( $self ) {
    $self->{sequence_number}++
};

sub current_sequence( $self ) {
    $self->{sequence_number}
};

sub build_url( $self, %options ) {
    $options{ host } ||= $self->{host};
    $options{ port } ||= $self->{port};
    my $url = sprintf "http://%s:%s/json", $options{ host }, $options{ port };
    $url .= '/' . $options{domain} if $options{ domain };
    $url
};

=head2 C<< $chrome->json_get >>

=cut

sub json_get($self, $domain, %options) {
    my $url = $self->build_url( domain => $domain, %options );
    $self->ua->http_get( $url )->then( sub( $payload, $headers ) {
        Future->done( $self->json->decode( $payload ))
    });
};

=head2 C<< $chrome->send_message >>

Expects a response!

=cut

sub send_message( $self, $method, %params ) {
    my $id = $self->next_sequence;
    my $payload = $self->json->encode({
        id => $id,
        method => $method,
        params => \%params
    });

    my $response = AnyEvent::Future->new();
    $self->{receivers}->{ $id } = $response;
    $self->ws->send( $payload );
    $response
}

=head2 C<< $chrome->eval >>

=cut

sub eval( $self, $string ) {
    $self->send_message('Runtime.eval', expression => $string, returnByValue => 1 )
};


=head2 C<< $chrome->protocol_version >>

    print $chrome->protocol_version->get->{"Protocol-Version"};

=cut

sub protocol_version($self) {
    $self->json_get( 'version' )->then( sub( $payload ) {
        Future->done( $payload->{"Protocol-Version"});
    });
};

=head2 C<< $chrome->get_domains >>

=cut

sub get_domains( $self ) {
    $self->send_message('Schema.getDomains');
}

=head2 C<< $chrome->list_tabs >>

=cut

sub list_tabs( $self ) {
    return $self->json_get('list')
};

=head2 C<< $chrome->new_tab >>

=cut

sub activate_tab( $self, $tab ) {
    return $self->json_get('new/'+ $tab->{id})
};

=head2 C<< $chrome->activate_tab >>

=cut

sub activate_tab( $self, $tab ) {
    return $self->json_get('activate/'+ $tab->{id})
};

=head2 C<< $chrome->close_tab >>

=cut

sub activate_tab( $self, $tab ) {
    return $self->json_get('close/'+ $tab->{id})
};


package Chrome::DevToolsProtocol::Tab;
use strict;
use Data::Dumper;

sub new {
    my ($class, %args) = @_;
    $args{ outstanding } ||= []; # XXX rename to 'queue'
    $args{ seq } ||= 0;
    bless \%args => $class;
};

sub handle_packet {
    my ($self,$headers,$payload) = @_;
    if ('attach' eq $payload->{ command }) {
        # we just got connected
        warn "Tab just connected";
    } elsif ('response' eq $payload->{ data }->{type}
         or  'event'    eq $payload->{ data }->{type}) {
        my $handler = shift @{ $self->{outstanding} };
        if ($handler) {
            $handler->send( $headers, $payload );
        } else {
            warn "Tab: Ignoring reply";
            warn Dumper [$headers, $payload];
        };
    } else {
        warn "Event for Tab $self->{id}";
        warn Dumper [$headers, $payload];
    };
};

sub request {
    my ($self,$payload) = @_;
    my $headers = {
         Tool => 'V8Debugger',
         Destination => $self->{id},
    };
    $payload->{ command } ||= 'debugger_command';
    $payload->{ data }->{ seq } = $self->{ seq }++;
    $payload->{ data }->{ type } = 'request';

    my $reply = AnyEvent->condvar;
    push @{ $self->{outstanding} }, $reply;
    #warn "Sending debugger request " . Dumper $payload;
    # This always has seq / request_seq, so we should do a proper wait here!
    # See http://code.google.com/p/v8/wiki/DebuggerProtocol
    $self->{ connection }->request( $headers, $payload );
    $reply->recv;
};

# Unfortunately, this has no return type :-/
sub eval {
    my ($self,$expr) = @_;
    $self->request({
        command => 'evaluate_javascript',
        #command => 'evaluate',
        data => {
            arguments => $expr,
            frame => 0, # always take the current stack frame
            global => 0,
            disable_break => 1,
        },
    });
};

1;