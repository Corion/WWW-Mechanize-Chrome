package Chrome::DevToolsProtocol::Transport;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

our $VERSION = '0.08';

=head1 NAME

Chrome::DevToolsProtocol::Transport - choose the best transport backend

=cut

our @loops = (
    ['Mojo/IOLoop.pm' => 'Chrome::DevToolsProtocol::Transport::Mojo' ],
    ['IO/Async.pm'    => 'Chrome::DevToolsProtocol::Transport::NetAsync'],
    ['AnyEvent.pm'    => 'Chrome::DevToolsProtocol::Transport::AnyEvent'],
    ['AE.pm'          => 'Chrome::DevToolsProtocol::Transport::AnyEvent'],
    # native POE support would be nice
    
    # The fallback, will always catch due to loading strict (for now)
    ['strict.pm'      => 'Chrome::DevToolsProtocol::Transport::AnyEvent'],
);
our $implementation;

=head1 METHODS

=head2 C<< Chrome::DevToolsProtocol::Transport->new() >>

    my $ua = Chrome::DevToolsProtocol::Transport->new();

Creates a new instance of the transport using the "best" event loop
for implementation. The default event loop is currently L<AnyEvent>.

=cut

sub new($factoryclass, @args) {
    $implementation ||= $factoryclass->best_implementation();
    
    # return a new instance
    $implementation->new(@args);
}

sub best_implementation( $class, @candidates ) {
    
    if(! @candidates) {
        @candidates = @loops;
    };

    # Find the currently running/loaded event loop(s)
    #use Data::Dumper;
    #warn Dumper \%INC;
    #warn Dumper \@candidates;
    my @applicable_implementations = map {
        $_->[1]
    } grep {
        $INC{$_->[0]}
    } @candidates;
    
    # Check which one we can load:
    for my $impl (@applicable_implementations) {
        if( eval "require $impl; 1" ) {
            return $impl;
        };
    };
};

=head1 SUPPORTED BACKENDS

The module will try to guess the best backend to use. The currently supported
backends are

=over 4

=item *

L<IO::Async>

=item *

L<AnyEvent>

=item *

L<Mojolicious>

=back

If you want to substitute another backend, pass its class name instead
of this module which only acts as a factory.

=cut

1;