package Chrome::DevToolsProtocol::Transport::NetAsync;
use strict;
use Moo 2;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';
use IO::Async::Loop;

use Net::Async::WebSocket::Client;
Net::Async::WebSocket::Client->VERSION(0.12); # fixes some errors with masked frames

our $VERSION = '0.37';

=head1 NAME

Chrome::DevToolsProtocol::Transport::NetAsync - IO::Async backend for Chrome communication

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    my $t = Chrome::DevToolsProtocol::Transport::NetAsync->new;
    $t->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=cut

has 'type' => (
    is => 'ro',
    default => 'websocket'
);

has 'loop' => (
    is => 'lazy',
    default => sub { IO::Async::Loop->new() },
);

has 'connection' => (
    is => 'rw',
);

sub connect( $self, $handler, $got_endpoint, $logger ) {
    $logger ||= sub{};
    weaken $handler;

    my $client;
    $got_endpoint->then( sub( $endpoint ) {
        $client = Net::Async::WebSocket::Client->new(
            # Kick off the continous polling
            on_frame => sub {
                my( $connection, $message )=@_;
                $handler->on_response( $connection, $message )
            },
            on_read_eof => sub {
                my( $connection )=@_;
                $logger->('info', "Connection closed");
                # TODO: should we tell handler?
            },
        );

        # Patch unlimited frame size into the client so we can receive large
        # buffers. This should become an RT ticket against Net::Async::WebSocket::Client
        $client->{framebuffer} = Protocol::WebSocket::Frame->new(
            max_payload_size => undef
        );

        $self->loop->add( $client );
        $self->{connection} ||= $client;

        die "Got an undefined endpoint" unless defined $endpoint;
        $logger->('debug',"Connecting to $endpoint");
        $client->connect( url => $endpoint, on_connected => sub {
            $logger->('info',"Connected to $endpoint");
        } );
    })->catch(sub{
        #require Data::Dumper;
        #warn "caught";
        #warn Data::Dumper::Dumper( \@_ );
        Future->fail( @_ );
    });
}

sub send( $self, $message ) {
    $self->connection->send_text_frame( $message )
}

sub close( $self ) {
    my $c = delete $self->{connection};
    if( $c) {
        $c->close
    };
}

sub future( $self ) {
    my $res = $self->loop->new_future;
    return $res
}

=head2 C<< $transport->sleep( $seconds ) >>

    $transport->sleep( 10 )->get; # wait for 10 seconds

Returns a Future that will be resolved in the number of seconds given.

=cut

sub sleep( $self, $seconds ) {
    $self->loop->delay_future( after => $seconds )
}

1;

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=WWW-Mechanize-Chrome>
or via mail to L<www-mechanize-Chrome-Bugs@rt.cpan.org|mailto:www-mechanize-Chrome-Bugs@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2018 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
