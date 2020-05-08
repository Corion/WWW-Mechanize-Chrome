#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 5;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my $html = $mech->content;
    like $html, qr!<html><head></head><body></body></html>!, "We can get the plain HTML";

    my $html2 = $mech->content( format => 'html' );
    is $html2, $html, "When asking for HTML explicitly, we get the same text";

    my $text = $mech->content( format => 'text' );
    is $text, '', "We can get the plain text";

    my $text2;
    my $lives = eval { $mech->content( format => 'bogus' ); 1 };
    ok !$lives, "A bogus content format raises an error";
});
