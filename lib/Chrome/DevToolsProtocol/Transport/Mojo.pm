package Chrome::DevToolsProtocol::Transport::Mojo;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use Mojo::UserAgent;
use Future::Mojo;

use vars qw<$VERSION $magic>;
$VERSION = '0.01';

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    my $t = Chrome::DevToolsProtocol::Transport::Mojo->new;
    $t->connect( $handler, $got_endpoint, $logger)
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

    my $client;
    $got_endpoint->then( sub( $endpoint ) {
        $client = Mojo::UserAgent->new;

        $logger->('DEBUG',"Connecting to $endpoint");
        my $res = $self->future;
        $client->websocket( $endpoint, sub( $ua, $tx ) {
            $self->{ua} = $ua;
            $res->done( $tx );
        });
        $res

    })->then( sub( $c ) {
        $logger->( 'DEBUG', sprintf "Connected" );
        my $connection = $c;
        $self->{connection} = $connection;
        undef $self;

        # Kick off the continous polling
        $connection->on( message => sub( $connection,$message) {
        warn "Message: $message";
            $handler->on_response( $connection, $message )
        });

        Future->done( $connection )
    });
}

sub send( $self, $message ) {
    $self->connection->send( $message )
}

sub close( $self ) {
    $self->connection->finish
        if $self->connection;
    delete $self->{connection};
    delete $self->{ua};
}

sub future {
    Future::Mojo->new
}

1;