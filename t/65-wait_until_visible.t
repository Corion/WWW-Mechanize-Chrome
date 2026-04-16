#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;

use strict;
use Test::More;
use Cwd;
use URI;
use URI::file;
use File::Basename;
use File::Spec;
use File::Temp 'tempdir';
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my @files = qw<
     65-is_visible_none_to_visible.html
>;

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => (4*@files+5)*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 4*@files+5, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    # Check that we can execute JS
    t::helper::safe_get_local($mech, $files[0]);
    $mech->allow('javascript' => 1);
    my ($triggered,$type,$ok);
    eval {
        ($triggered, $type) = t::helper::safe_eval_in_page($mech, 'timer');
        $ok = 1;
    };
    if (! $triggered) {
        SKIP: {
            skip("Couldn't get at 'timer'. Do you have a Javascript blocker?", 4*@files +5);
        };
        return;
    };
    # Check that we can trigger the timeout
    for my $file ($files[0]) {
        t::helper::safe_get_local($mech, $file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        ok !$mech->is_visible(selector => '#retry'), "The element is invisible";
        my $finished = eval {
            $mech->wait_until_visible(selector => '#retry', timeout => ($t::helper::is_slow ? 10 : 1));
            1;
        };
        is $finished, undef, "We got an exception";
        like $@, qr/Timeout/, "We got a timeout error message";
    };

    for my $file (@files) {
        t::helper::safe_get_local($mech, $file);
        is $mech->title, $file, "We loaded the right file ($file)";
        $mech->allow('javascript' => 1);
        my ($timer,$type) = t::helper::safe_eval_in_page($mech, 'timer');
        ok $mech->is_visible(selector => 'body'), "We can see the body";

        if(! ok !$mech->is_visible(selector => '#retry'), "We can't see #retry") {
            my $standby = t::helper::safe_by_id($mech, 'standby', single=>1);
            my $style = $standby->{style};
            diag "style.visibility          <" . $style->{visibility} . ">";
            diag "style.display             <" . $style->{display} . ">";
            #$style = $window->getComputedStyle($standby, undef);
            diag "computed-style.visibility <" . $style->{visibility} . ">";
            diag "computed-style.display    <" . $style->{display} . ">";
        };
        t::helper::safe_click($mech, { selector => '#start' });
        $mech->wait_until_visible( selector => "#retry" );
        ok $mech->is_visible(selector => '#retry'), "We can see #retry now";
    };

    note "End of test sub for $browser_instance";
});

alarm(0);
