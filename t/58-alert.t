#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
use Data::Dumper;

use Log::Log4perl qw(:easy);

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
    plan tests => 4*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

sub load_file_ok {
    my ($mech, $htmlfile,@options) = @_;
    my $fn = File::Spec->rel2abs(
                 File::Spec->catfile(dirname($0),$htmlfile),
                 getcwd,
             );
    #$mech->allow(@options);
    #diag "Loading $fn";
    t::helper::safe_get_local($mech, $fn);
    ok $mech->success, "Loading $htmlfile is considered a success";
    is $mech->title, $htmlfile, "We loaded the right file (@options)"
        or diag $mech->content;
};

t::helper::run_across_instances(\@instances, \&new_mech, 4, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my @alerts;
    my $alert_f = Future->new;

    $mech->on_dialog( sub {
        my ( $mech, $dialog ) = @_;
        push @alerts, $dialog;
        $mech->handle_dialog(1); # I always click "OK", why?
        if (@alerts == 2) {
            $alert_f->done if !$alert_f->is_ready;
        }
        # Give Windows a moment to breath before the next alert
        Time::HiRes::sleep(0.1) if $^O =~ /mswin/i;
    });

    load_file_ok($mech, '58-alert.html', javascript => 1);

    # Wait up to 20s for both alerts to arrive
    my $wait_start = time;
    my $timeout_f = $mech->sleep_future(20)->then(sub { Future->fail("Timed out waiting for alerts") });
    eval { Future->wait_any($alert_f, $timeout_f)->get };
    if ($@) {
        note "Alert wait finished after " . (time - $wait_start) . "s: $@";
    }

    is 0+@alerts, 2, "got two alerts"
        or diag explain \@alerts;

    undef $mech;
});

alarm(0);
