#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use lib 'inc', '../inc', '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 5*@instances;
};

my %args;
sub new_mech {
    # Just keep these to pass the parameters to new instances
    if( ! keys %args ) {
        %args = @_;
    };
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        %args,
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 5, sub {
    my($browser_instance, $mech)= @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my ($site,$estatus) = ('http://'.rand(1000).'.www.doesnotexist.example/',500);
    my $res = $mech->get($site);

    #is $mech->uri, $site, "Navigating to (nonexisting) $site";

    if( ! isa_ok $res, 'HTTP::Response', 'The response') {
        SKIP: { skip "No response returned", 1 };
    } else {
        my $c = $res->code;
        like $res->code, qr/^(404|5\d\d)$/, "GETting $site gives a 5xx (no proxy) or 404 (proxy)"
            or diag $mech->content;

        like $mech->status, qr/^(404|5\d\d)$/, "GETting $site returns a 5xx (no proxy) or 404 (proxy) HTTP status"
            or diag $mech->content;
    };

    ok !$mech->success, 'We consider this response not successful';
});