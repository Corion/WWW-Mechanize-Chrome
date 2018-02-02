#!perl -w
use strict;
use lib './t/';
use helper;
use WWW::Mechanize::Chrome;
use File::Glob qw( bsd_glob );
use Config;
use Getopt::Long;
use Algorithm::Loops 'NestedLoops';

GetOptions(
    't|test:s' => \my $tests,
    'b|backend:s' => \my $backend,
    'c|continue' => \my $continue,
);
my @tests;
if( $tests ) {
    @tests= bsd_glob( $tests );
};

=head1 NAME

runtests.pl - runs the test suite versions of Chrome and with different backends

=cut

my @instances = @ARGV
                ? map { bsd_glob $_ } @ARGV 
                : t::helper::browser_instances;
my $port = 9222;

$backend ||= qr/./;
my @backends = grep { /$backend/i } (qw(
    Chrome::DevToolsProtocol::Transport::AnyEvent
    Chrome::DevToolsProtocol::Transport::Mojo
));
#   Chrome::DevToolsProtocol::Transport::NetAsync

my $windows = ($^O =~ /mswin/i);

# Later, we could even parallelize the test suite
NestedLoops( [\@instances, \@backends], sub {
    my( $instance, $backend ) = @_;
    system "taskkill /IM chrome.exe /F" if $windows; # boom, kill all leftover Chrome versions

    ## Launch one Chrome instance to reuse
    my $vis_instance = $instance;
    $ENV{TEST_WWW_MECHANIZE_CHROME_VERSIONS} = $instance;
    $ENV{WWW_MECHANIZE_CHROME_TRANSPORT} = $backend;
    warn "Testing $vis_instance with $backend";
    #my @launch = $instance
    #           ? (launch => [$instance,'-repl', $port, 'about:blank'])
    #           : ()
    #           ;
    #
    #if( $instance ) {
    #    $ENV{TEST_WWW_MECHANIZE_FIREFOX_VERSIONS} = $instance;
    #    $ENV{MOZREPL}= "localhost:$port";
    #} else {
    #    $ENV{TEST_WWW_MECHANIZE_FIREFOX_VERSIONS} = "don't test other instances";
    #    delete $ENV{MOZREPL}; # my local setup ...
    #};
    #my $retries = 3;
    #
    #my $ff;
    #while( $retries-- and !$ff) {
    #    $ff= eval {
    #        Firefox::Application->new(
    #            @launch,
    #        );
    #    };
    #};
    #die "Couldn't launch Firefox instance from $instance"
    #    unless $ff;
    
    if( @tests ) {
        for my $test (@tests) {
            system(qq{perl -Ilib -w "$test"}) == 0
                or ($continue and warn "Error while testing $vis_instance + $backend: $!/$?")
                or die "Error while testing $vis_instance: $!/$?";
        };
    } else { # run all tests
        system("$Config{ make } test") == 0
            or ($continue and warn "Error while testing $vis_instance + $backend: $!/$?")
            or die "Error while testing $vis_instance";
    };
    
    #undef $ff;
    ## Safe wait until shutdown
    #sleep 5;
    system "taskkill /IM chrome.exe /F" if $windows; # boom, kill all leftover Chrome versions
});