#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc', '.';
use t::helper;
use Test::HTTP::LocalServer;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 14*@instances;
};

use Data::Dumper;

sub new_mech {
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
    diag "Loading $fn";
    $mech->get_local($fn);
    ok $mech->success, "Loading $htmlfile is considered a success";
    is $mech->title, $htmlfile, "We loaded the right file (@options)"
        or diag $mech->content;
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 14, sub {
    my ($firefox_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    load_file_ok($mech, '49-mech-get-file.html', javascript => 0);

    is $mech->content_type, 'text/html', "HTML content type";

    $mech->get('about:blank');
    load_file_ok($mech, '49-mech-get-file.html', javascript => 1);
    $mech->get('about:blank');

    $mech->get_local('49-mech-get-file.html');
    ok $mech->success, '49-mech-get-file.html';
    is $mech->title, '49-mech-get-file.html', "We loaded the right file";

    ok $mech->is_html, "The local file gets identified as HTML"
        or diag $mech->content;

    $mech->get_local('49-mech-get-file-lc-ct.html');
    ok $mech->success, '49-mech-get-file-lc-ct.html';
    is $mech->title, '49-mech-get-file-lc-ct.html', "We loaded the right file";
    ok $mech->is_html, "The local file gets identified as HTML even with a weird-cased http-equiv attribute"
        or diag $mech->content;
    is $mech->content_type, 'text/html', "HTML content type is read from http-equiv meta tag";

    $mech->get_local('file-does-not-exist.html');
    ok !$mech->success, 'We fail on non-existing file';
        #or diag $mech->content;
});
