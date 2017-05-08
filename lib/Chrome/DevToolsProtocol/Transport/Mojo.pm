package Chrome::DevToolsProtocol::Transport::Mojo;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

use Mojo::UserAgent;
use Future::Mojo qw(as_future_cb);

use vars qw<$VERSION $magic>;
$VERSION = '0.01';

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    Chrome::DevToolsProtocol::Transport::AnyEvent->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=cut

sub connect( $class, $handler, $got_endpoint, $logger ) {
    $logger ||= sub{};

    my $client;
    $got_endpoint->then( sub( $endpoint ) {
        $client = Mojo::UserAgent->new;

        $logger->('DEBUG',"Connecting to $endpoint");
        my $res = Future::Mojo->new();
        $client->websocket( $endpoint, sub( $ua, $tx ) {
            $res->done( $tx );
        });

    })->then( sub( $c ) {
        $logger->( 'DEBUG', sprintf "Connected" );
        my $connection = $c;

        # Kick off the continous polling
        $connection->on( message => sub( $connection,$message) {
            $handler->on_response( $connection, $message )
        });

        Future->done( $connection )
    });
}

1;