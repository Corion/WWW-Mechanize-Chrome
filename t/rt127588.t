#! /usr/bin/perl -w
use strict;

use Log::Log4perl qw( :easy );
use WWW::Mechanize::Chrome;

use Test::More;

use lib '.';
use t::helper;

Log::Log4perl -> easy_init ( $ERROR );

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 1*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        launch_arg => [
            "--no-sandbox",
            "--disable-suid-sandbox",
            '--headless',
        ],
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 1, sub {
    pass "We didn't crash when disabling the suid sandbox";
});
