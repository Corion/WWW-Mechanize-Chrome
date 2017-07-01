package Chrome::DevToolsProtocol::Transport;
use strict;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

use vars qw($implementation @loops $VERSION);
$VERSION = '0.04';

=head1 NAME

Chrome::DevToolsProtocol::Transport - choose the best transport backend

=cut

@loops = (
    ['Mojo/IOLoop.pm' => 'Chrome::DevToolsProtocol::Transport::Mojo' ],
    ['AnyEvent.pm'    => 'Chrome::DevToolsProtocol::Transport::AnyEvent'],
    ['AE.pm'          => 'Chrome::DevToolsProtocol::Transport::AnyEvent'],
    # POE support would be nice
    # IO::Async support would be nice, using Net::Async::HTTP
    
    # The fallback, will always catch due to loading strict (for now)
    ['strict.pm'      => 'Chrome::DevToolsProtocol::Transport::AnyEvent'],
);

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

1;