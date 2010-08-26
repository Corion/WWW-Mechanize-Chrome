package Chrome::DevToolsProtocol::Extension;
use strict;
use strict;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Carp qw(croak carp);
use JSON;
use Data::Dumper;

sub new {
    my ($class, %args) = @_;
    
    carp "No id given"
        unless $args{ id };
       
    $args{ port } ||= undef; # not connected
    $args{ queue } ||= [];
    my $self = bless \%args => $class;
    $self->connect($args{ id });
    
    $self
};

# Send a request and return the next response, fifo order
sub request {
    my ($self, $headers, $body) = @_;
    my $cv = $self->push_read;
    $self->{ client }->write_request( $headers, $body );
    $cv->recv;
};

sub push_read {
    my ($self) = @_;
    my $cv = AnyEvent->condvar;
    push @{ $self->{queue} }, $cv;
    $cv
};

sub connect {
    my ($self, $id) = @_;
    carp "No id given"
        unless $id;
    $self->{id} = $id;
    my ($headers, $response) = $self->{ client }->request(
        { 'Tool' => 'ExtensionPorts' },
        { 'command' => 'connect',
          'data' => { 'extensionId' => $self->{id} } }
    );
    $self->{port} = $response->{data}->{portId};

    # XXX Set up ourselves as a packet destination    
    $self->{ client }->{ receivers }->{ 'ExtensionPorts' }->{ $self->{port} } = sub {
        $self->handle_packet( @_ );
    };
    warn "Connected to port $self->{port}";
};

sub disconnect {
    my ($self) = @_;
    my ($headers, $response) = $self->request(
        { 'Tool' => 'ExtensionPorts', Destination => $self->{port} },
        { 'command' => 'disconnect',
          'data' => { 'extensionId' => $self->{id} } }
    );
};

sub handle_packet {
    # Called for every packet that goes in our direction
    my ($self,$headers,$payload) = @_;
    if (my $waiting = shift @{ $self->{ queue }}) {
        $waiting->send( $headers, $payload );
    } else {
        warn "Ignoring packet " . Dumper [$headers, $payload];
    };
};

sub post {
    my ($self,$data) = @_;
    my ($headers, $response) = $self->request(
        { 'Tool' => 'ExtensionPorts', Destination => $self->{port} },
        { 'command' => 'postMessage',
          'data' => $data }
    );
    ($headers,$response)
};

sub eval {
    my ($self,$js,@args) = @_;
    my $json_args = to_json(\@args);
    my ($h,$r) = $self->post(
           "(function(){return $js}).apply(null,$json_args)",
    );
    #warn "Evaluated JS";
    ($h,$r) = $self->push_read()->recv;
    $r->{data}->{success}
};

1;