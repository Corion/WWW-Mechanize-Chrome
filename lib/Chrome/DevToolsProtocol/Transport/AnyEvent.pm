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

our $VERSION = '0.16';
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

        my $res = $self->future;
        $logger->('debug',"Connecting to $endpoint");
        $client = AnyEvent::WebSocket::Client->new(
            max_payload_size => 0, # allow unlimited size for messages
        );
        $client->connect( $endpoint )->cb( sub {
            $res->done( @_ )
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
    $self->connection->send( $message );
    $self->future->done(1);
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
    AnyEvent::Future->new_delay( after => $seconds );
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
