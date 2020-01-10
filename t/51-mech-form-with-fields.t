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

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 6*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, \&new_mech, 6, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    $mech->get_local('51-mech-submit.html');
    my $f = $mech->form_with_fields(
       'r',
    );
    ok $f, "We found the form";

    $mech->get_local('51-mech-submit.html');
    $f = $mech->form_with_fields(
       'q','r',
    );
    ok $f, "We found the form";

    SKIP: {
        #skip "Chrome frame support is wonky.", 2;

        $mech->get_local('52-frameset.html');
        $f = $mech->form_with_fields(
           'baz','bar',
        );
        ok $f, "We found the form in a frame";

        $mech->get($server->local('52-iframeset.html'));
        $mech->sleep(1); # debug for AppVeyor failures?!
        my $ok = eval {
            $f = $mech->form_with_fields(
                'baz','bar',
            );
            1;
        };
        is $ok, 1, "We didn't crash"
            or diag $@;
        ok $f, "We found the form in an iframe";
    };
});
$server->stop;
