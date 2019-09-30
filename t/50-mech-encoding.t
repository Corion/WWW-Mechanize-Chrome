#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use lib '.';

use t::helper;

my @tests = (
    [ 'mixi_jp_index.html', 'EUC-JP', qr/\x{30DF}\x{30AF}\x{30B7}\x{30A3}/ ],
    [ 'sophos_co_jp_index.html', 'SHIFT_JIS', qr/\x{30B0}\x{30ED}\x{30FC}\x{30D0}\x{30EB}/ ],
);
my $testcount = 2*@tests;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    for (@tests) {
            my ($file,$encoding,$content_re) = @$_;
            $mech->get_local($file);
            is uc $mech->content_encoding, $encoding, "$file has encoding $encoding";
            note "Length of content", length $mech->content;
            like $mech->content, $content_re, "Partial expression gets found in UTF-8 content";
    };
});
