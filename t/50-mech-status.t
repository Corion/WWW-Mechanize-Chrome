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

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 5*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 5, sub {
    my($browser_instance, $mech)= @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my ($site,$estatus) = ('https://'.rand(1000).'.www.doesnotexist.example/',500);
    my $res = $mech->get($site);

    #is $mech->uri, $site, "Navigating to (nonexisting) $site";

    if( ! isa_ok $res, 'HTTP::Response', 'The response') {
        SKIP: { skip "No response returned", 2 };
    } else {
        my $c = $res->code;
        like $res->code, qr/^(404|5\d\d)$/, "GETting $site gives a 5xx (no proxy) or 404 (proxy)"
            or diag $mech->content;

        like $mech->status, qr/^(404|5\d\d)$/, "GETting $site returns a 5xx (no proxy) or 404 (proxy) HTTP status"
            or diag $mech->content;
    };

    ok !$mech->success, 'We consider this response not successful';
});
