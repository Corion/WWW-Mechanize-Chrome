package Chrome::DevToolsProtocol::Transport::AnyEvent;
use strict;
use Filter::signatures;
use Moo 2;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use Carp qw(croak);

use AnyEvent;
use AnyEvent::WebSocket::Client;
use AnyEvent::Future qw(as_future_cb);

our $VERSION = '0.66';
our @CARP_NOT = ();

=head1 NAME

Chrome::DevToolsProtocol::Transport::AnyEvent - AnyEvent backend for Chrome communication

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    Chrome::DevToolsProtocol::Transport::AnyEvent->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=cut

has 'type' => (
    is => 'ro',
    default => 'websocket'
);

has 'connection' => (
    is => 'rw',
);

has 'ws_client' => (
    is => 'rw',
);

sub connect( $self, $handler, $got_endpoint, $logger ) {
    weaken $handler;
    weaken(my $s = $self);

    local @CARP_NOT = (@CARP_NOT, 'Chrome::DevToolsProtocol::Transport');

    croak "Need an endpoint to connect to" unless $got_endpoint;
    $self->close;

    $got_endpoint->then( sub( $endpoint ) {
        die "Got an undefined endpoint" unless defined $endpoint;

        my $res = $s->future;
        $logger->('debug',"Connecting to $endpoint");
        $s->ws_client( AnyEvent::WebSocket::Client->new(
            max_payload_size => 0, # allow unlimited size for messages
        ));
        $s->ws_client->connect( $endpoint )->cb( sub {
            $res->done( @_ )
        });
        $res

    })->then( sub( $c ) {
        $logger->( 'trace', sprintf "Connected" );
        my $connection = $c->recv;

        $s->connection( $connection );
        #undef $self;

        # Kick off the continous polling
        $connection->on( each_message => sub( $connection,$message, @rest) {
            # I haven't investigated what @rest contains...
            $handler->on_response( $connection, $message->body )
        });
        $connection->on( parse_error => sub( $connection, $error) {
            $logger->('error', $error);
        });

        my $res = Future->done( $s );
        undef $s;
        $res
    });
}

sub send( $self, $message ) {
    if( my $c = $self->connection ) {
        $c->send( $message );
    };
    $self->future->done(1);
}

sub close( $self ) {
    my $c = delete $self->{connection};
    $c->close
        if $c;
    delete $self->{ws_client};
}

# Maybe we should keep track of the callstacks of our ->future()s
# and when they get lost, so we can more easily pinpoint the locations?!
sub future {
    my $f = AnyEvent::Future->new;
    #use Carp qw(cluck); cluck "Producing new future $f";
    return $f;
}

=head2 C<< $transport->sleep( $seconds ) >>

    $transport->sleep( 10 )->get; # wait for 10 seconds

Returns a Future that will be resolved in the number of seconds given.

=cut

sub sleep( $self, $seconds ) {
    AnyEvent::Future->new_delay( after => $seconds );
}

1;

=head1 REQUIRED ADDITIONAL MODULES

This module needs additional modules that are not installed by the default
installation of WWW::Mechanize::Chrome:

L<AnyEvent>

L<AnyEvent::WebSocket::Client>

L<AnyEvent::Future>


=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the Github bug queue at
L<https://github.com/Corion/WWW-Mechanize-Chrome/issues>

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2021 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
