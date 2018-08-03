#!perl
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
use File::Temp 'tempdir';

use lib '.';
use WWW::Mechanize::Chrome;
use t::helper;

my @instances = t::helper::browser_instances();
my $windows = ($^O =~ /mswin/i);

for my $instance (@instances) {
    #system "taskkill /IM chrome.exe /F" if $windows; # boom, kill all leftover Chrome versions

    my $mech = WWW::Mechanize::Chrome->new(
        launch_exe => $instance,
        headless   => 1,
        incognito  => 1,
        data_directory => tempdir( CLEANUP => 1 ),
    );
    print $mech->chrome_version, "\n";
}