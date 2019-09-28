package Chrome::DevToolsProtocol::Transport::Pipe;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use Scalar::Util 'weaken';

use IO::Async::Loop;
use IO::Async::Stream;

our $VERSION = '0.36';

=head1 NAME

Chrome::DevToolsProtocol::Transport::Pipe - EXPERIMENTAL Local pipe backend for Chrome communication

=head1 SYNOPSIS

    my $t = Chrome::DevToolsProtocol::Transport::Pipe->new;
    $t->connect( $handler, $got_endpoint, $logger)
    ->then(sub {
        my( $connection ) = @_;
        print "We are connected\n";
    });

=head1 DESCRIPTION

This is an experimental backend communicating with Chrome using a pipe
of two file descriptors. At least on Debian, this backend does not implement


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

    my $buffer;

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
                    $handler->on_response( $self, $line );
                };;
            },
        );
        $self->{loop}->add( $self->connection );
        Future->done( $self );
    });
}

sub send( $self, $message ) {
    $self->connection->write( $message . "\0" );
    $self->future->done(1);
}

sub close( $self ) {
    my $c = delete $self->{connection};
    if( $c) {
        $c->close
    };
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

Copyright 2010-2019 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
