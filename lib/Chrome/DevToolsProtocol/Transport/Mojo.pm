package Chrome::DevToolsProtocol::Transport::Mojo;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use Mojo::UserAgent;
use Future::Mojo;

our $VERSION = '0.20';

=head1 NAME

Chrome::DevToolsProtocol::Transport::Mojo - Mojolicious backend for Chrome communication

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

    $got_endpoint->then( sub( $endpoint ) {
        $self->{ua} ||= Mojo::UserAgent->new();
        my $client = $self->{ua};

        $logger->('debug',"Connecting to $endpoint");
        die "Got an undefined endpoint" unless defined $endpoint;
        my $res = $self->future;
        #$client->on( 'start' => sub { $logger->('trace', "Starting transaction", @_ )});
        $client->websocket( $endpoint, { 'Sec-WebSocket-Extensions' => 'permessage-deflate' }, sub( $ua, $tx ) {
            # On error we get an Mojolicious::Transaction::HTTP here
            if( $tx->is_websocket) {
                $logger->('trace',"Connected to $endpoint");
                $res->done( $tx );
            } else {
                my $msg = "Couldn't connect to endpoint '$endpoint': " . $tx->res->error->{message};
                $logger->('trace', $msg);
                $tx->finish();
                $res->fail( $msg );
            }
        });
        $res

    })->then( sub( $c ) {
        my $connection = $c;
        $self->{connection} ||= $connection;

        # Kick off the continous polling
        $connection->on( message => sub( $connection,$message) {
            warn "Hmm - the Websocket handler went away but I got a message for them" if( ! $handler );
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
    if( my $c = delete $self->{connection}) {
        $c->finish
    };
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
    Future::Mojo->new_timer( $seconds )
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
