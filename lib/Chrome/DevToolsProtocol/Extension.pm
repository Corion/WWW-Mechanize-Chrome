package Chrome::DevToolsProtocol::Extension;
use strict;
use strict;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Carp qw(croak);
use JSON;
use Data::Dumper;

sub new {
    my ($class, %args) = @_;
       
    my $self = bless \%args => $class;
    $self->connect($args{ id });
    
    $self
};

sub connect {
    my ($self, $id) = @_;
    $self->{id} = $id;
    my ($headers, $response) = $self->{client}->request(
        { 'Tool' => 'ExtensionPorts' },
        { 'command' => 'connect',
          'data' => { 'extensionId' => $self->{id} } }
    );
    $self->{port} = $response->{data}->{portId};
};

sub disconnect {
    my ($self) = @_;
    my ($headers, $response) = $self->{client}->request(
        { 'Tool' => 'ExtensionPorts', Destination => $self->{port} },
        { 'command' => 'disconnect',
          'data' => { 'extensionId' => $self->{id} } }
    );
};

sub command {
    my ($self,$data) = @_;
    my ($headers, $response) = $self->{client}->request(
        { 'Tool' => 'ExtensionPorts', Destination => $self->{port} },
        { 'command' => 'postMessage',
          'data' => $data }
    );
};

sub eval {
    my ($self,$js) = @_;
    
};

1;