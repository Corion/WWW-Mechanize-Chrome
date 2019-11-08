#!perl
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
use File::Temp 'tempdir';
use File::Glob 'bsd_glob';

use lib '.';
use WWW::Mechanize::Chrome;
use t::helper;

my @instances = @ARGV
                ? map { bsd_glob $_ } @ARGV
                : t::helper::browser_instances;
my $windows = ($^O =~ /mswin/i);

for my $instance (@instances) {
    #system "taskkill /IM chrome.exe /F" if $windows; # boom, kill all leftover Chrome versions
    print WWW::Mechanize::Chrome->chrome_version(
        launch_exe => $instance,
    ), "\n";
}