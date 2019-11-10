#!perl -w
use strict;
use lib './t/';
use helper;
use WWW::Mechanize::Chrome;
use File::Glob qw( bsd_glob );
use Config;
use Getopt::Long;
use Algorithm::Loops 'NestedLoops';
use File::Temp 'tempdir';

GetOptions(
    't|test=s' => \my @tests,
    'b|backend=s' => \my $backend,
    'c|continue' => \my $continue,
    's|separate-instances=s' => \my $separate_instances,
    'level|l=s' => \my $log_level,
);
if( @tests ) {
    @tests= map { bsd_glob( $_ ) } @tests;
};

if( ! defined $separate_instances) {
    $separate_instances = 1;
}

if( $ENV{HARNESS_OPTIONS} and $ENV{HARNESS_OPTIONS}=~ /\bj\d+/) {
    die "Mixing parallel tests and a single browser instance spells danger"
        if ! $separate_instances;
};

=head1 NAME

runtests.pl - runs the test suite versions of Chrome and with different backends

=head1 USAGE

  # On unixish OSes
  HARNESS_OPTIONS=j12 perl -Ilib -w development/runtests.pl --separate-instances=1

  # On Windows
  set HARNESS_OPTIONS=j12
  perl -Ilib -w development/runtests.pl --separate-instances=1

=cut

my @instances = @ARGV
                ? map { bsd_glob $_ } @ARGV
                : t::helper::browser_instances;

$backend ||= qr/./;
my @backends = grep { /$backend/i } (qw(
    Chrome::DevToolsProtocol::Transport::AnyEvent
    Chrome::DevToolsProtocol::Transport::Mojo
    Chrome::DevToolsProtocol::Transport::NetAsync
    Chrome::DevToolsProtocol::Transport::Pipe::AnyEvent
    Chrome::DevToolsProtocol::Transport::Pipe::Mojo
    Chrome::DevToolsProtocol::Transport::Pipe::NetAsync
));

my $windows = ($^O =~ /mswin/i);
delete $ENV{CHROME_BIN};

# At least until I implement proper fd passing for Windows:
if( $windows ) {
    @backends = grep {! /::Pipe::/ } @backends;
};

sub kill_chrome {
    if( $windows ) {
        system "taskkill /IM chrome.exe /F" if $windows; # boom, kill all leftover Chrome versions
    } else {
        system "killall chromium"; # boom, kill all leftover Chromium versions
        system "killall chrome";   # boom, kill all leftover Chrome versions
    };
}

# Later, we could even parallelize the test suite
NestedLoops( [\@instances, \@backends], sub {
    my( $instance, $backend ) = @_;

    kill_chrome();

    ## Launch one Chrome instance to reuse
    my $vis_instance = $instance;
    $ENV{TEST_WWW_MECHANIZE_CHROME_VERSIONS} = $instance;
    $ENV{WWW_MECHANIZE_CHROME_TRANSPORT} = $backend;
    if( $log_level ) {
        $ENV{TEST_LOG_LEVEL} = $log_level;
    };
    warn "Testing $vis_instance with $backend";

    my $launch_master = !$separate_instances;
    my $testrun;
    if( $launch_master ) {
        # Launch a single process we will reuse for all these tests
        my $tempdir = tempdir( CLEANUP => 1 );
        $testrun = WWW::Mechanize::Chrome->new(
            launch_exe     => $instance,
            data_directory => $tempdir,
            headless       => 1,
        );
        $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE}= join ":", $testrun->driver->host, $testrun->driver->port;
    } else {
        delete $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE};
    };
    $ENV{TEST_WWW_MECHANIZE_CHROME_VERSIONS} = $instance;

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

    if( $testrun ) {
        undef $testrun;
        sleep 2;
    };

    ## Safe wait until shutdown
    #sleep 5;
});
kill_chrome();
