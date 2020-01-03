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

my $have_test_memory_cycle = eval {;
    require Test::Memory::Cycle;
    1;
};

sub no_memory_cycles_ok {
    my( $mech, $name ) = @_;
    if( $have_test_memory_cycle ) {
        Test::Memory::Cycle::memory_cycle_ok($mech, "No cycles $name");
    } else {
        SKIP: {
            skip "Test::Memory::Cycle needed for deeper leak testing", 1;
        };
    };
}

sub load_file_ok {
    my ($mech, $htmlfile,@options) = @_;
    my $fn = File::Spec->rel2abs(
                 File::Spec->catfile(dirname($0),$htmlfile),
                 getcwd,
             );
    #$mech->allow(@options);
    #diag "Loading $fn";
    $mech->get_local($fn);
    ok $mech->success, "Loading $htmlfile is considered a success";
    is $mech->title, $htmlfile, "We loaded the right file (@options)"
        or diag $mech->content;
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    $mech = new_mech( headless => 1 );
    no_memory_cycles_ok( $mech, "at the start" );
    my $old_destroy = $mech->can('DESTROY');
    my $called = 0;
    no warnings 'redefine';
    local *WWW::Mechanize::Chrome::DESTROY = sub {
        $called++;
        goto &$old_destroy;
    };

    my @alerts;

    $mech->on_dialog( sub {
        my ( $mech, $dialog ) = @_;
        push @alerts, $dialog;
        $mech->handle_dialog(1); # I always click "OK", why?
    });

    load_file_ok($mech, '58-alert.html', javascript => 1);
    no_memory_cycles_ok( $mech, "after an alert()" );
    undef $mech;
    is $called, 1, "We destroyed our object after ->on_dialog";

    $called = 0;
    note "Constructing fresh mechanize";
    $mech = new_mech( headless => 1 );
    $mech->setScreenFrameCallback(sub {});
    $mech->sleep(0.1);
    $mech->setScreenFrameCallback();
    no_memory_cycles_ok( $mech, "after a screen cast frame" );
    undef $mech;
    is $called, 1, "We destroyed our object after a frame was grabbed";

    $called = 0;
    $mech = new_mech( headless => 1 );
    $mech->get_local('49-mech-get-file.html');
    my @results = $mech->xpath('//*');
    no_memory_cycles_ok( $mech, "after an xpath search" );
    undef $mech;
    is $called, 1, "We destroyed our object after a search was performed";
});
