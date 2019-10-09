#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Chrome::DevToolsProtocol::Transport;
use Chrome::DevToolsProtocol::Transport::Pipe;

my $ok = eval {
    require Test::Without::Module;
    require Chrome::DevToolsProtocol::Transport::Mojo;
    1;
} || eval {
    require Test::Without::Module;
    require Chrome::DevToolsProtocol::Transport::IOAsync;
    1;
};

if( $ok ) {
    plan( tests => 2 );
} else {
    plan( skip_all => "No backend other than AnyEvent available" );
};

Test::Without::Module->import( qw( AnyEvent ) );
isn't( Chrome::DevToolsProtocol::Transport->best_implementation, 'AnyEvent',
    "We select a different socket backend if AnyEvent is unavailable");

isn't( Chrome::DevToolsProtocol::Transport::Pipe->best_implementation, 'AnyEvent',
    "We select a different pipe backend if AnyEvent is unavailable");
