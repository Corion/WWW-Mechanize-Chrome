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
$VERSION = '0.01';

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    Chrome::DevToolsProtocol::Transport::AnyEvent->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=cut

sub new( $class, %options ) {
    bless \%options => $class
}

sub connection( $self ) {
    $self->{connection}
}

sub connect( $self, $handler, $got_endpoint, $logger ) {
    $logger ||= sub{};
    weaken $handler;

    local @CARP_NOT = (@CARP_NOT, 'Chrome::DevToolsProtocol::Transport');

    croak "Need an endpoint to connect to" unless $got_endpoint;

    my $client;
    $got_endpoint->then( sub( $endpoint ) {
        die "Got an undefined endpoint" unless defined $endpoint;

        my $res = as_future_cb( sub( $done_cb, $fail_cb ) {
            $logger->('DEBUG',"Connecting to $endpoint");
            $client = AnyEvent::WebSocket::Client->new;
            $client->connect( $endpoint )->cb( $done_cb );
        });
        $res

    })->then( sub( $c ) {
        $logger->( 'DEBUG', sprintf "Connected" );
        my $connection = $c->recv;
        $self->{connection} = $connection;
        undef $self;

        # Kick off the continous polling
        $connection->on( each_message => sub( $connection,$message) {
            $handler->on_response( $connection, $message->body )
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

1;