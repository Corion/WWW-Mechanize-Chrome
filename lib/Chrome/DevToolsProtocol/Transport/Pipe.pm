package Chrome::DevToolsProtocol::Transport::Pipe;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

our $VERSION = '0.49';

=head1 NAME

Chrome::DevToolsProtocol::Transport::Pipe - choose the best pipe transport backend

=cut

our @loops;
push @loops, (
    ['Mojo/IOLoop.pm'   => 'Chrome::DevToolsProtocol::Transport::Pipe::Mojo' ],
    ['IO/Async.pm'      => 'Chrome::DevToolsProtocol::Transport::Pipe::NetAsync'],
    ['IO/Async/Loop.pm' => 'Chrome::DevToolsProtocol::Transport::Pipe::NetAsync'],
    ['AnyEvent.pm'      => 'Chrome::DevToolsProtocol::Transport::Pipe::AnyEvent'],
    ['AE.pm'            => 'Chrome::DevToolsProtocol::Transport::Pipe::AnyEvent'],
    # native POE support would be nice
);
our $implementation;
our $default = 'Chrome::DevToolsProtocol::Transport::Pipe::NetAsync';

=head1 METHODS

=head2 C<< Chrome::DevToolsProtocol::Transport::Pipe->new(@args) >>

    my $ua = Chrome::DevToolsProtocol::Transport::Pipe->new();

Creates a new instance of the transport using the "best" event loop
for implementation. The default event loop is currently L<AnyEvent>.

All parameters are passed on to the implementation class.

=cut

sub new($factoryclass, @args) {
    $implementation ||= $factoryclass->best_implementation();

    # Just in case a user has set this from the outside
    eval "require $implementation; 1";

    # return a new instance
    $implementation->new(@args);
}

sub best_implementation( $class, @candidates ) {

    if(! @candidates) {
        @candidates = @loops;
    };

    # Find the currently running/loaded event loop(s)
    #use Data::Dumper;
    #$Data::Dumper::Sortkeys = 1;
    #warn Dumper \%INC;
    #warn Dumper \@candidates;
    my @applicable_implementations = map {
        $_->[1]
    } grep {
        $INC{$_->[0]}
    } @candidates;

    if( ! @applicable_implementations ) {
        @applicable_implementations = ($default, map {$_->[1]} @candidates);
    }

    # Check which one we can load:
    for my $impl (@applicable_implementations) {
        if( eval "require $impl; 1" ) {
            return $impl;
        }
        # else { warn $@ };
    };

    # This will crash and burn, but that's how it is
    eval "require $default; 1";
    return $default;
};

1;

=head1 SUPPORTED BACKENDS

The module will try to guess the best backend to use. The currently supported
backends are

=over 4

=item *

L<IO::Async>

=item *

L<AnyEvent> (planned)

=item *

L<Mojolicious> (planned)

=back

If you want to substitute another backend, pass its class name instead
of this module which only acts as a factory.

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
