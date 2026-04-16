#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use Test::HTTP::LocalServer;
use WWW::Mechanize::Chrome;

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 6;

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

my $server = t::helper->safe_server(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    t::helper::safe_get_local($mech, '51-mech-submit.html');
    my $f = t::helper::safe_form_with_fields($mech,
       'r',
    );
    ok $f, "We found the form";

    t::helper::safe_get_local($mech, '51-mech-submit.html');
    $f = t::helper::safe_form_with_fields($mech,
       'q','r',
    );
    ok $f, "We found the form";

    SKIP: {
        #skip "Chrome frame support is wonky.", 2;

        t::helper::safe_get_local($mech, '52-frameset.html');
        $f = t::helper::safe_form_with_fields($mech,
           'baz','bar',
        );
        ok $f, "We found the form in a frame";

        t::helper::safe_get($mech, $server->local('52-iframeset.html'));
        $mech->sleep(1); # debug for AppVeyor failures?!
        my $ok = eval {
            $f = t::helper::safe_form_with_fields($mech,
                'baz','bar',
            );
            1;
        };
        is $ok, 1, "We didn't crash"
            or diag $@;
        ok $f, "We found the form in an iframe";
    };

    note "End of test sub for $browser_instance";
});

alarm(0);

$server->stop;

