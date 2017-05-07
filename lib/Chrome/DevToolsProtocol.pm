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
    #$args{ sequence_number } ||= 1;
    # XXX Make receivers multi-level on Tool+Destination
    # XXX Make receivers store callbacks instead of one-shot condvars?
    
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
        if( @args ) {
            warn "$level: $message";
        } else {
            warn "$level: $message " . Dumper \@args;
        };
    };
}

sub connect( $self, %args ) {
    # Kick off the connect
    
    my $endpoint = $args{ endpoint } || $self->endpoint;

    my $got_endpoint;
    if( ! $endpoint ) {
    
        # find the debugger endpoint:
        # These are the open tabs
        $got_endpoint = $self->json_get('')->then(sub($tabs) {
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
            my $payload = $message;
            die "Message: " . Dumper $payload;
            #$self->handle_packet($headers,$payload);
        });
        
        $self->{ws} = $connection;
        Future->done( $connection )
    });
};

# Handles any response packet from Chrome and
# decides whether it's an event or a response
sub handle_packet {
    my ($self,$headers,$payload) = @_;
    warn "Received packet: " . Dumper [$headers,$payload];
    # Now dispatch to the proper Destination
    # Empty destination means "connection"
    my $dest = defined $headers->{ Destination } 
               ? $headers->{ Destination } 
               : '';
    my $tool = $headers->{ Tool } || '';
    
    # Dispatch simply based on all headers
    # Also, discriminate between coderef and condvar
    # Only delete condvars, keep coderefs
    my $handler = $self->{receivers}->{$tool}->{$dest};
    if ($handler) {
        if ('CODE' eq (ref $handler)) {
            $handler->( $headers, $payload );
        } else {
            # If it's a CondVar, remove it from the list
            delete $self->{receivers}->{$tool}->{$dest};
            $handler->send( $headers, $payload );
        };
    } else {
        warn "Unknown response destination '$tool/$dest', ignored";
        warn Dumper [$headers,$payload];
    };
};

sub write_request {
    my ($self, $headers, $body) = @_;
    # XXX What about UTF8 ? The protocol seems to count CHARACTERS,
    # not bytes. We-ird.
    my $json = $self->{json}->encode($body);
    $headers->{'Content-Length'} = length $json;
    my $fh = $self->{chrome};
    while (my ($k,$v) = each %$headers) {
        $fh->push_write("$k:$v\r\n");
    };
    $fh->push_write("\r\n");
    $fh->push_write($json);
    #warn "Wrote " . Dumper $headers;
    #warn "Wrote $json";
};

sub next_sequence {
    $_[0]->{sequence_number}++
};

sub current_sequence {
    $_[0]->{sequence_number}
};

sub request {
    my ($self, $headers, $body) = @_;
    #$headers->{Destination} ||= '';
    my $repl_sender = $headers->{Destination} || '';
    my $tool = $headers->{Tool} || '';
    my $got = $self->queue_response($headers->{Destination}, $headers->{Tool});
    $self->write_request( $headers, $body );
    #print "Waiting for reply from '$tool/$repl_sender'\n";
    my @data = $got->recv;
    #print "Got reply from '$tool/$repl_sender'\n";
    @data
};

sub queue_response {
    my ($self, $destination, $tool) = @_;
    my $got = AnyEvent->condvar;
    $destination //= ''; # //
    #warn "Listening on $tool/$destination";
    $self->{receivers}->{$tool} ||= {};
    $self->{receivers}->{$tool}->{$destination} ||= AnyEvent->condvar;
};

sub extension {
    my ($self,$id) = @_;
    Chrome::DevToolsProtocol::Extension->new(
        id => $id,
        client => $self,
    );
};

# Only good for naked commands, no payload
sub command {
    my ($self,$command, $data) = @_;
    my ($h,$d) = $self->request(
        { Tool => 'DevToolsService' }, { command => $command },
    );
    $d->{data};
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


=head2 C<< $chrome->protocol_version >>

    print $chrome->protocol_version->get->{"Protocol-Version"};

=cut

sub protocol_version($self) {
    $self->json_get( 'version' )->then( sub( $payload ) {
        Future->done( $payload->{"Protocol-Version"});
    });
};

=head2 C<< $chrome->list_tabs >>

=cut

sub list_tabs( $self, $url ) {
    return $self->ua->http_get($url)->then(sub($payload,$headers) {
        my $res = $self->json->decode( $payload );
        Future->done($res)
    });
};

sub attach {
    my ($self, $tab_id) = @_;
    my $tab = Chrome::DevToolsProtocol::Tab->new(
        connection => $self, # should be weakened
        id => $tab_id,
    );
    my $cv;
    my $forward; $forward = sub {
        # Check whether we get a "detach" reply?
        # Otherwise forward packet
        #warn "Forwarding " . Dumper \@_;
        # Ideally, we would keep track of outstanding sequence numbers
        # and dispatch the responses to them
        # but the ExtensionPorts don't have the seq / request_seq field :(
        $tab->handle_packet( $_[0]->recv );
        
        # Reinstate the callback
        $cv = AnyEvent->condvar;
        $cv->cb( $forward );
        $self->{receivers}->{V8Debugger}->{$tab_id} = $cv;
    };
    $cv = AnyEvent->condvar;
    $cv->cb( $forward );
    $self->{receivers}->{V8Debugger}->{$tab_id} = $cv;

    #warn "Requesting attach to $tab_id";
    my ($d,$h) = $self->request(
        { Tool => 'V8Debugger', Destination => $tab_id, },
        { command => 'attach' },
    );
    # We should return a ::Tab object or something?
    # Do we really want to?    
    $tab
};

#sub extension {
#    my ($self,$name) = @_;
#    my $ext = Chrome::DevToolsProtocol::Extension->new(
#        id => $name,
#        client => $self, # weaken this ...
#        port => 9,
#    );
#    $ext->connect($name);
#    $ext
#};

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