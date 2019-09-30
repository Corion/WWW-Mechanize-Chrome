#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
use Data::Dumper;

use WWW::Mechanize::Chrome;
use lib '.';
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 25*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

sub load_file_ok {
    my ($mech, $htmlfile,@options) = @_;
    $mech->clear_js_errors;
    $mech->allow(@options);
    $mech->get_local($htmlfile);
    ok $mech->success, $htmlfile;
    is $mech->title, $htmlfile, "We loaded the right file (@options)";
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, \&new_mech, 25, sub {

    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';
    can_ok $mech, 'js_errors','clear_js_errors';


    $mech->clear_js_errors;
    is_deeply [$mech->js_errors], [], "No errors reported on page after clearing errors"
        or diag Dumper [$mech->js_errors];

    load_file_ok($mech, '53-mech-capture-js-noerror.html', javascript => 1);
    my ($js_ok) = eval { $mech->eval_in_page('js_ok') };
    if (! $js_ok) {
        SKIP: { skip "Couldn't get at 'js_ok' variable. Do you have a Javascript blocker enabled for file:// URLs?", 14; };
        undef $mech;
        exit;
    };

    my @res= $mech->js_errors;
    is_deeply \@res, [], "No errors reported on page"
        or diag $res[0]->{message};

    load_file_ok($mech, '53-mech-capture-js-noerror.html', javascript => 1 );
    @res= $mech->js_errors;
    is_deeply \@res, [], "No errors reported on page"
        or diag Dumper \@res;

    {
        my $errors;
        local $mech->{report_js_errors} = 1;
        local $SIG{__WARN__} = sub { $errors = shift };
        load_file_ok($mech, '53-mech-capture-js-noerror.html', javascript => 1 );
        ok( not(defined $errors), "No errors reported on page")
            or diag Dumper $errors;
    };

    load_file_ok($mech,'53-mech-capture-js-error.html', javascript => 0);
    note "File loaded";
    @res= $mech->js_errors;
    is_deeply \@res, [], "Errors on page"
        or diag Dumper \@res;
    {
        my $errors;
        local $mech->{report_js_errors} = 1;
        # We should find out how to make Log::Log4perl call our callback so
        # we can check that the error message arrives in our logger ...
        no warnings 'redefine';
        local *WWW::Mechanize::Chrome::log = sub { $errors = $_[2] if $_[1] eq 'error' };
        load_file_ok($mech, '53-mech-capture-js-error.html', javascript => 1 );
        ok( defined $errors, "Errors on page");
    };

    load_file_ok($mech,'53-mech-capture-js-error.html', javascript => 1);
    my @errors = $mech->js_errors;
    is scalar @errors, 1, "One error message found";
    (my $msg) = @errors;
    like $msg->{exceptionDetails}->{exception}->{description}, qr/^ReferenceError: nonexisting_function is not defined/, "Errors message"
        or diag Dumper $msg;
    like $msg->{exceptionDetails}->{stackTrace}->{callFrames}->[0]->{url}, qr!\Q53-mech-capture-js-error.html\E!, "File name";
    is $msg->{exceptionDetails}->{stackTrace}->{callFrames}->[0]->{lineNumber}, 5, "Line number";

    $mech->clear_js_errors;
    is_deeply [$mech->js_errors ], [], "No errors reported on page after clearing errors";

    undef $mech; # global destruction ...

});
