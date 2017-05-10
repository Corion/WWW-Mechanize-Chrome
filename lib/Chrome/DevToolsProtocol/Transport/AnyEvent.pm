package Chrome::DevToolsProtocol::Transport::AnyEvent;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

use AnyEvent;
use AnyEvent::WebSocket::Client;
use AnyEvent::Future qw(as_future_cb);

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

        as_future_cb( sub( $done_cb, $fail_cb ) {
            $logger->('DEBUG',"Connecting to $endpoint");
            $client = AnyEvent::WebSocket::Client->new;
            $client->connect( $endpoint )->cb( $done_cb );
        });

    })->then( sub( $c ) {
        $logger->( 'DEBUG', sprintf "Connected" );
        my $connection = $c->recv;

        # Kick off the continous polling
        $connection->on( each_message => sub( $connection,$message) {
            $handler->on_response( $connection, $message )
        });

        return Future->done( $connection )
    });
}

sub future {
    AnyEvent::Future->new
}

1;