package Chrome::DevToolsProtocol::Transport::Mojo;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use Mojo::UserAgent;
use Future::Mojo;

use vars qw<$VERSION>;
$VERSION = '0.07';

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

        $logger->('debug',"Connecting to $endpoint");
        die "Got an undefined endpoint" unless defined $endpoint;
        my $res = $self->future;
        $client->websocket( $endpoint, sub( $ua, $tx ) {
            $logger->('trace',"Connected to $endpoint");
            $self->{ua} = $ua;
            # On error we get an Mojolicious::Transaction::HTTP here
            if( $tx->is_websocket) {
                $res->done( $tx );
            } else {
                $res->fail( "Couldn't connect to endpoint '$endpoint': " . $tx->res->error->{message});
            }
        });
        $res

    })->then( sub( $c ) {
        my $connection = $c;
        $self->{connection} ||= $connection;

        # Kick off the continous polling
        $connection->on( message => sub( $connection,$message) {
            $handler->on_response( $connection, $message )
        });

        my $res = Future->done( $self );
        undef $self;
        $res
    });
}

sub send( $self, $message ) {
    $self->connection->send( $message );
    $self->future->done(1);
}

sub close( $self ) {
    my $c = delete $self->{connection};
    $c->finish
        if $c;
    delete $self->{ua};
}

sub future {
    Future::Mojo->new
}

=head2 C<< $transport->sleep( $seconds ) >>

    $transport->sleep( 10 )->get; # wait for 10 seconds

Returns a Future that will be resolved in the number of seconds given.

=cut

sub sleep( $self, $seconds ) {
    my $done = $self->future;
    my $t; $t = Mojo::IOLoop->timer( $seconds => sub {
        undef $t;
        $done->done(1);
    });
    $done
}

1;