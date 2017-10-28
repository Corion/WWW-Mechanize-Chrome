package Chrome::DevToolsProtocol::Transport::AnyEvent;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use Carp qw(croak);

use AnyEvent;
use AnyEvent::WebSocket::Client;
use AnyEvent::Future qw(as_future_cb);

use vars qw<$VERSION $magic @CARP_NOT>;
$VERSION = '0.06';

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    Chrome::DevToolsProtocol::Transport::AnyEvent->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=cut

sub new( $class, %options ) {
    my $self = \%options;
    bless $self => $class;
    $self
}

sub connection( $self ) {
    $self->{connection}
}

sub connect( $self, $handler, $got_endpoint, $logger ) {
    weaken $handler;

    local @CARP_NOT = (@CARP_NOT, 'Chrome::DevToolsProtocol::Transport');

    croak "Need an endpoint to connect to" unless $got_endpoint;

    my $client;
    $got_endpoint->then( sub( $endpoint ) {
        die "Got an undefined endpoint" unless defined $endpoint;

        my $res = as_future_cb( sub( $done_cb, $fail_cb ) {
            $logger->('debug',"Connecting to $endpoint");
            $client = AnyEvent::WebSocket::Client->new(
                max_payload_size => 0, # allow unlimited size for messages
            );
            $client->connect( $endpoint )->cb( $done_cb );
        });
        $res

    })->then( sub( $c ) {
        $logger->( 'trace', sprintf "Connected" );
        my $connection = $c->recv;

        $self->{connection} = $connection;
        undef $self;

        # Kick off the continous polling
        $connection->on( each_message => sub( $connection,$message, @rest) {
            # I haven't investigated what @rest contains...
            $handler->on_response( $connection, $message->body )
        });
        $connection->on( parse_error => sub( $connection, $error) {
            $logger->('error', $error);
        });

        my $res = Future->done( $self );
        undef $self;
        $res
    });
}

sub send( $self, $message ) {
    $self->connection->send( $message )
}

sub close( $self ) {
    my $c = delete $self->{connection};
    $c->close
        if $c;
}

sub future {
    AnyEvent::Future->new
}

=head2 C<< $transport->sleep( $seconds ) >>

    $transport->sleep( 10 )->get; # wait for 10 seconds

Returns a Future that will be resolved in the number of seconds given.

=cut

sub sleep( $self, $seconds ) {

    my $res = as_future_cb( sub( $done_cb, $fail_cb ) {
        AnyEvent->timer( after => $seconds, cb => $done_cb )
    });
}

1;
