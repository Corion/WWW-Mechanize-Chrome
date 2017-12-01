package Chrome::DevToolsProtocol::Transport::NetAsync;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';
use IO::Async::Loop;

use Net::Async::WebSocket::Client;

use vars qw<$VERSION>;
$VERSION = '0.07';

=head1 NAME

Chrome::DevToolsProtocol::Transport::NetAsync - IO::Async backend

=head1 SYNOPSIS

    my $got_endpoint = Future->done( "ws://..." );
    my $t = Chrome::DevToolsProtocol::Transport::NetAsync->new;
    $t->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=cut

sub new( $class, %options ) {
    $options{ loop } ||= IO::Async::Loop->new();
    bless \%options => $class
}

sub connection( $self ) {
    $self->{connection}
}

sub loop( $self ) {
    $self->{loop}
}

sub connect( $self, $handler, $got_endpoint, $logger ) {
    $logger ||= sub{};
    weaken $handler;

    $got_endpoint->then( sub( $endpoint ) {
        die "Got an undefined endpoint" unless defined $endpoint;
        my $client = $self->{connection} ||= Net::Async::WebSocket::Client->new(
            # Kick off the continous polling
            on_frame => sub {
                my( $connection, $message )=@_;
                $logger->('trace', "Got message", $message );
                $handler->on_response( $connection, $message )
            },
            on_read_eof => sub {
                my( $connection )=@_;
                $logger->('info', "Connection closed");
                # TODO: should we tell handler?
            },
        );
        $self->loop->add( $client );

        $logger->('debug',"Connecting to $endpoint");
        $client->connect( url => $endpoint, on_connected => sub {
            $logger->('info',"Connected to $endpoint");
        } );
    })->catch(sub{
        require Data::Dumper;
        warn Data::Dumper::Dumper \@_;
    });
}

sub send( $self, $message ) {
    $self->connection->send_frame( $message )
}

sub close( $self ) {
    my $c = delete $self->{connection};
    $c->finish
        if $c;
    delete $self->{ua};
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