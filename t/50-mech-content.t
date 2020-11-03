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
my $testcount = 9;

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

    my $version = $mech->chrome_version;
    if( $version =~ /\b(\d+)\b/ and $1 < 80 ) {
        SKIP: {
            skip "Chrome version is $version, need Chrome version 80 for MHTML", 2;
        };
    } else {
        my $mhtml = $mech->content( format => 'mhtml' );
        like $mhtml, qr/^Snapshot-Content-Location:/m, "We can get the MHTML of the whole page";

        $mech->get_local('52-frameset.html');
        $mhtml = $mech->content( format => 'mhtml' );
        like $mhtml, qr!<title>52-subframe.html</title>!, "We can get the MHTML of the whole page, including frames";
    };

    my $text2;
    my $lives = eval { $mech->content( format => 'bogus' ); 1 };
    ok !$lives, "A bogus content format raises an error";

    {
        local $TODO = "Chrome devtools doesn't return the XML declaration of a document";
        $mech->get_local('xhtml.xhtml');
        $html = $mech->content;
        like $html, qr/^<?xml\b/, "->content preserves the XHTML directive";
    }

    # pm11123357
    $mech->get_local('scripttag.html');
    $text = $mech->content( format => 'text' );
    like $text, qr/^\s*This should appear.\s+This should also appear.\s*$/, "<script> tag contents are not included in text";
});
