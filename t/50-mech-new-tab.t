#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use Test::HTTP::LocalServer;
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 8;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

my $url = $server->url;

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

    $mech->get($url);
    my $org_uri = $mech->uri;

    my $tab = $mech->new_tab();
    isa_ok $tab, 'WWW::Mechanize::Chrome';
    $tab->get('about:blank');

    is $mech->uri, $org_uri, "The URI of the original mech remains unchanged";

    my $new_count = 0;
    $tab->cookie_jar->scan(sub{$new_count++});

    my $old_count = 0;
    $mech->cookie_jar->scan(sub{$old_count++});
    is $new_count, $old_count, "We have the same number of cookies in the two tabs";

    # Now, move one, to see that the tabs are independent
    $tab->get($url);
    $mech->submit_form( with_fields => { query => 'original mech' });
    $tab->submit_form( with_fields => { query => 'secondary mech' });

    $mech->sleep(1); # to give the tabs a chance to catch up
    is $mech->uri, "${url}formsubmit", "We moved the original tab";
    like $mech->content, qr/\boriginal mech\b/, "The original tab has the new content";
    is $tab->uri, "${url}formsubmit", "We moved the second tab";
    like $tab->content, qr/\bsecondary mech\b/, "The second tab has the other content";
});

$server->stop;
