package Chrome::DevToolsProtocol::Transport::Pipe::AnyEvent;
use strict;
use Filter::signatures;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Moo 2;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use Carp qw(croak);

use AnyEvent;
use AnyEvent::Future qw(as_future_cb);

our $VERSION = '0.52';
our @CARP_NOT = ();

=head1 NAME

Chrome::DevToolsProtocol::Transport::Pipe::AnyEvent- EXPERIMENTAL Local pipe backend for Chrome communication

=head1 SYNOPSIS

    my $t = Chrome::DevToolsProtocol::Transport::Pipe::AnyEvent->new;
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

has 'endpoint' => (
    is => 'rw',
);

has 'reader' => (
    is => 'rw',
);

has 'writer' => (
    is => 'rw',
);

sub connect( $self, $handler, $got_endpoint, $logger ) {
    $logger ||= sub{};
    weaken $handler;

    my $buffer = '';

    weaken( my $s = $self );

    $got_endpoint->then( sub( $endpoint ) {
        die "Got an undefined endpoint" unless defined $endpoint;
        $self->endpoint( $endpoint ); # keep a reference
        my $flags = fcntl( $endpoint->{ reader_fh }, F_GETFL, 0 );
        fcntl( $endpoint->{ reader_fh }, F_SETFL, $flags | O_NONBLOCK )
            or warn "Can't make the pipe nonblocking: $!";
        my $reader = AnyEvent->io(
            fh  => $endpoint->{ reader_fh },
            poll => 'r',
            cb => sub {
                # Append to our buffer
                sysread( $s->endpoint->{ reader_fh }, $buffer, 4096, length($buffer));
                while($buffer =~ s!^(.*?)\0!!) {
                    my $line = $1;
                    $handler->on_response( $s, $line );
                };
            },
        );
        $self->reader($reader);

        # We cheat here and write synchronously ...
        #my $writer = AnyEvent->io(
        #    fh => $endpoint->{ writer_fh },
        #    poll => 'w',
        #);
        $endpoint->{writer_fh}->autoflush(1);
        $self->writer($endpoint->{writer_fh});
        Future->done( $self );
    });
}

sub send( $self, $message ) {
    print { $self->writer } $message . "\0"
        or warn $!;
    $self->future->done(1);
}

sub close( $self ) {
    delete $self->{reader};
    delete $self->{writer};
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

Copyright 2010-2020 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
