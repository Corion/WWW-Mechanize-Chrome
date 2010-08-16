package Chrome::DevToolsProtocol;
use strict;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Carp qw(croak);
use JSON;
use Data::Dumper;
use Chrome::DevToolsProtocol::Extension;

use vars qw<$VERSION $magic>;
$VERSION = '0.01';
$magic = "ChromeDevToolsHandshake";

sub new {
    my ($class, %args) = @_;
    
    my $self = bless \%args => $class;
    
    $args{ host } ||= 'localhost';
    $args{ port } ||= 9222;
    $args{ json } ||= JSON->new;
    $args{ sequence_number } ||= 1;
    $args{ receivers } ||= {};
    
    # Kick off the connect
    my $connected = AnyEvent->condvar;
    $self->{chrome} = AnyEvent::Handle->new( connect => [ $args{ host }, $args{ port } ], on_connect => sub {
        my ($fh) = @_;
        $self->{chrome} ||= $fh;
        
        # Send the id
        $self->{chrome}->push_write("$magic\r\n");
        $self->{chrome}->push_read(line => "\r\n", sub {
            my ($handle,$line) = @_;
            
            if ($line ne $magic) {
                croak "Did not get magic response (got '$line')";
            };
            $connected->send;
        }); # read the response
    });
    
    # How can (should?) we do/pass this asynchronously?
    $connected->recv;
    
    # Kick off the continous polling
    $self->{chrome}->on_read( sub {
        my $fh = $_[0];
        #print "Data available\n";
        #my $complete = AnyEvent->condvar();
        $fh->push_read( line => "\r\n\r\n", sub {
            #print "Headers consumed\n";
            # Deparse headers
            my $headers = +{ $_[1] =~ /^([^:]+):([^\r\n]*)[\r\n]*$/mg };
            
            $fh->unshift_read( json => sub {
                #print "Payload consumed\n";
                my $payload = $_[1];
                $self->handle_packet($headers,$payload);
                #$complete->send($headers, $payload);
            });
        });
        #my ($headers,$payload) = $complete->recv;
    });
    
    $self
};

# Handles any response packet from Chrome and
# decides whether it's an event or a response
sub handle_packet {
    my ($self,$headers,$payload) = @_;
    warn "Received packet: " . Dumper [$headers,$payload];
    # Now dispatch to the proper Destination
    # Empty destination means "connection"
    my $dest = $headers->{ Destination } || '';
    #warn Dumper $self->{receivers};
    
    if (defined( my $recv = delete $self->{receivers}->{ $dest })) {
        warn "Sending to Destination $dest";
        $recv->send( $headers, $payload );
    } else {
        warn "Unknown response destination '$dest', ignored";
        warn Dumper [$headers,$payload];
    };
    #if (ref $payload->{data}) {
    #    my $t = $payload->{data}->{type};
    #    if ('response' eq $t) {
    #        my $id = $payload->{request_seq};
    #        my $catch = delete ($self->{outstanding}->{ $id });
    #        if ($catch) {
    #            $catch->send($headers,$payload);
    #        } else {
    #            warn "Discarding response for unknown request " . Dumper [$headers,$payload];
    #        };
    #        delete ($self->{outstanding}->{ $id })->send($headers,$payload);
    #    } elsif ('event' eq $t) {
    #        warn "Ignoring event " . Dumper [$headers, $payload];
    #    } else {
    #        warn "Unknown type '$t'";
    #    };
    #};
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
};

sub next_sequence {
    $_[0]->{sequence_number}++
};

sub current_sequence {
    $_[0]->{sequence_number}
};

sub request {
    my ($self, $headers, $body) = @_;
    $self->write_request( $headers, $body );
    #my $res = $self->read_response_async();
    # Enqueue our condvar with our handle_packets    
    my $got = $self->queue_response($headers->{Destination});
    print "Waiting for reply from $headers->{Destination}\n";
    my @data = $got->recv;
    warn Dumper \@data;
    @data
};

sub queue_response {
    my ($self, $destination) = @_;
    #warn "Discarding response handler for '$destination'"
    #    if ($self->{receivers}->{$destination});
    my $got = AnyEvent->condvar;
    $self->{receivers}->{$destination} ||= AnyEvent->condvar;
    #$got
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

sub protocol_version {
    $_[0]->command('version');
};

sub list_tabs {
    @{ $_[0]->command('list_tabs') || [] };
};

sub attach {
    my ($self, $tab_id, $handler) = @_;
    my $tab = Chrome::DevToolsProtocol::Tab->new(
        connection => $self, # should be weakened
        id => $tab_id,
    );
    my $cv;
    my $forward; $forward = sub {
        # Check whether we get a "detach" reply?
        # Otherwise forward packet
        #warn "Forwarding " . Dumper \@_;
        $tab->handle_packet( $_[0]->recv );
        
        # Reinstate the callback
        $cv = AnyEvent->condvar;
        $cv->cb( $forward );
        $self->{receivers}->{$tab_id} = $cv;
    };
    $cv = AnyEvent->condvar;
    $cv->cb( $forward );
    $self->{receivers}->{$tab_id} = $cv;

    #warn "Requesting attach to $tab_id";
    my ($d,$h) = $self->request(
        { Tool => 'V8Debugger', Destination => $tab_id, },
        { command => 'attach' },
    );
    # We should return a ::Tab object or something?
    # Do we really want to?    
    $tab
};

package Chrome::DevToolsProtocol::Tab;
use strict;
use Data::Dumper;

sub new {
    my ($class, %args) = @_;
    $args{ outstanding } ||= [];
    $args{ seq } ||= 0;
    bless \%args => $class;
};

sub handle_packet {
    my ($self,$headers,$payload) = @_;
    if ('response' eq $payload->{ data }->{type}) {
        my $handler = shift @{ $self->{outstanding} };
        if ($handler) {
            $handler->send( $headers, $payload );
        } else {
            warn "Ignoring reply";
            warn Dumper [$headers, $payload];
        };
    } else {
        warn "Event for $self->{id}";
        warn Dumper [$headers, $payload];
    };
};

sub request {
    my ($self,$payload) = @_;
    my $headers = {
         Tool => 'V8Debugger',
         Destination => $self->{id},
    };
    $payload->{ command } = 'debugger_command';
    $payload->{ data }->{ seq } = $self->{ seq }++;
    $payload->{ data }->{ type } = 'request';
    
    my $reply = AnyEvent->condvar;
    push @{ $self->{outstanding} }, $reply;
    $self->{ connection }->request( $headers, $payload );
    $reply->recv;
};
    
1;