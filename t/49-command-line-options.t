#!perl

use warnings;
use strict;
use stable 'postderef';
use Test2::V0 '-no_srand';

use Log::Log4perl qw(:easy);
use Data::Dumper;

use WWW::Mechanize::Chrome;
use Getopt::Long 'GetOptionsFromArray'; # we reparse the command line we generate

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my %defaults = (
    'remote-debugging-port' => 9222,
    'no-first-run' => 1,
    'mute-audio' => 1,

    'disable-background-networking' => 1,
    'disable-gpu' => 1,
    'disable-hang-monitor' => 1,
    'disable-sync' => 1,
);
my @tests = (
    [{}, {
    }, "Default options"],
    [{temp_profile => 1}, { 'temp-profile' => 1 }, "Temp profile is passed through"],
);
my $test_count = 0+@tests;
plan tests => $test_count;

for my $t (@tests) {
    my ($constructor,$expected,$name) = $t->@*;
    my @cmd = WWW::Mechanize::Chrome->build_command_line($constructor);
    my @org = @cmd;
    my $exe = shift @cmd;
    GetOptionsFromArray(\@cmd,
        \my %opts,
        'remote-debugging-port=s',
        'temp-profile',

        'no-first-run',
        'mute-audio',
        'remote-allow-origins',

        # The toggles
        'disable-background-networking',
        'enable-background-networking',
        'disable-gpu',
        'enable-gpu',
        'disable-hang-monitor',
        'enable-hang-monitor',
        'disable-sync',
        'enable-sync',
    );

    my %test = (%defaults, $expected->%*);
    is \%opts, \%test, $name
        or diag Dumper \@cmd;
};

done_testing();
