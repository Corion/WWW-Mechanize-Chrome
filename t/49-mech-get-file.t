#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;

use WWW::Mechanize::Chrome;
use lib '.';
use t::helper;
use Test::HTTP::LocalServer;

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 12*@instances;
};

use Data::Dumper;

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        log => sub { my ($message, @info ) = @_; diag $message, Dumper \@info },
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
    ok $mech->success, $htmlfile;
    is $mech->title, $htmlfile, "We loaded the right file (@options)"
        or diag $mech->content;
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 12, sub {
    my ($firefox_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    load_file_ok($mech, '49-mech-get-file.html', javascript => 0);
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

    $mech->get_local('file-does-not-exist.html');
    ok !$mech->success, 'We fail on non-existing file'
        or diag $mech->content;
});
