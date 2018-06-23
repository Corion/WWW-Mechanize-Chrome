#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use File::Temp 'tempdir';

use WWW::Mechanize::Chrome;
use lib './inc', '../inc', '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

my $testcount = 3;
if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;
    my $version = $mech->chrome_version;

    if( $version =~ /\b(\d+)\b/ and $1 < 60 ) {
        SKIP: {
            skip "Chrome before v60 doesn't list all frame parts", $testcount;
        };
        return
    };
    
    isa_ok $mech, 'WWW::Mechanize::Chrome';
    
    my $topdir = tempdir( CLEANUP => 1 );
    $mech->get($server->url);
    #my %r = $mech->saveResources_future(
    #    "test page.html"
    #)->get();
    #is_deeply \%r, {
    #    $server->url => 'test page.html',
    #}, "We return a map of the saved files"
    #    or diag Dumper \%r;

    #$mech->get('http://corion.net/econsole/');
    #$mech->get('http://corion.net/');
    my $page_file = "$topdir/test page.html";
    my %r = $mech->saveResources_future(
        target_file => $page_file,
    )->get();
    
    ok -f $page_file, "Top HTML file exists";
    is $r{ $server->url }, $page_file,
        "We save the URL under the top HTML filename"
        or diag Dumper \%r;
});
$server->kill;
undef $server;
