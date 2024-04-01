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
    require Chrome::DevToolsProtocol::Transport::AnyEvent;
    1;
};

if( $ok ) {
    plan( tests => 2 );
} else {
    plan( skip_all => "No backend other than IO::Async available" );
};

Test::Without::Module->import( qw( Net::Async::HTTP ) );
isnt( Chrome::DevToolsProtocol::Transport->best_implementation, 'Chrome::DevToolsProtocol::Transport::NetAsync',
    "We select a different socket backend if IO::Async is unavailable");

isnt( Chrome::DevToolsProtocol::Transport::Pipe->best_implementation, 'Chrome::DevToolsProtocol::Transport::NetAsync',
    "We select a different pipe backend if IO::Async is unavailable");
