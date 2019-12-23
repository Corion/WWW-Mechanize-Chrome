package Chrome::DevToolsProtocol::Transport::Pipe::NetAsync;
use strict;
use Filter::signatures;
use Moo 2;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use IO::Async::Loop;
use IO::Async::Stream;

our $VERSION = '0.42';

=head1 NAME

Chrome::DevToolsProtocol::Transport::Pipe::NetAsync - EXPERIMENTAL Local pipe backend for Chrome communication

=head1 SYNOPSIS

    my $t = Chrome::DevToolsProtocol::Transport::Pipe::NetAsync->new;
    $t->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=head1 DESCRIPTION

This is an experimental backend communicating with Chrome using a pipe
of two file descriptors.

This requires Chrome v72+.

=cut

has 'type' => (
    is => 'ro',
    default => 'pipe'
);

has 'loop' => (
    is => 'lazy',
    default => sub {
        IO::Async::Loop->new(),
    },
);

has 'connection' => (
    is => 'rw',
);

sub connect( $self, $handler, $got_endpoint, $logger ) {
    $logger ||= sub{};
    weaken $handler;
    my $buffer;
    weaken( my $s = $self );
    $got_endpoint->then( sub( $endpoint ) {
        die "Got an undefined endpoint" unless defined $endpoint;
        $self->{connection} = IO::Async::Stream->new(
            read_handle  => $endpoint->{ reader_fh },
            write_handle => $endpoint->{ writer_fh },
            on_write_error => sub {
                use Data::Dumper;
                warn Dumper \@_;
            },
            on_read => sub( $self, $buffref, $eof ) {
                while($$buffref =~ s!^(.*?)\0!!) {
                    #warn "[[$1]]";
                    my $line = $1;
                    $handler->on_response( $s, $line );
                };
            },
        );
        $self->loop->add( $self->connection );
        Future->done( $self );
    });
}

sub send( $self, $message ) {
    $self->connection->write( $message . "\0" );
    $self->future->done(1);
}

sub close( $self ) {
    my $c = delete $self->{connection};
    my $l = delete $self->{loop};
    if( $c ) {
        #warn "*** Closing!";
        $c->close_now;
    };
    #if( $l ) {
    #    $l->remove( $c );
    #};
}

sub DESTROY {
    $_[0]->close();
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

=head1 SEE ALSO

The factory class for transports

L<Chrome::DevToolsProtocol::Transport::Pipe>

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

Copyright 2010-2019 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
