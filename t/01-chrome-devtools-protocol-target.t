#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Chrome::DevToolsProtocol;
use WWW::Mechanize::Chrome; # for launching Chrome
use Log::Log4perl qw(:easy);

use lib '.';
use t::helper;

my @instances = t::helper::browser_instances();
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my $testcount = 7;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $chrome = WWW::Mechanize::Chrome->new(
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my( $file, $mech ) = splice @_;
    my $chrome = $mech->driver;
    #undef $mech;

    isa_ok $chrome, 'Chrome::DevToolsProtocol::Target';

    my $version = $chrome->protocol_version->get;
    cmp_ok $version, '>=', '0.1', "We have a protocol version ($version)";

    my @tabs = $chrome->getTargets()->get;
    cmp_ok 0+@tabs, '>', 0,
        "We have at least one open (empty) tab";

    my $target_tab = $tabs[ 0 ];
    if( ! $target_tab->{targetId}) {
        SKIP: {
            skip "This Chrome doesn't want more than one debugger connection", 1;
        };
    } else {
        $chrome->connect(tab => $target_tab)->get();
        my $tab = $chrome->tab;
        isnt $tab, undef, "Attached to tab '$target_tab->{title}'";
    };

    my $res = $chrome->eval('1+1')->get;
    is $res, 2, "Simple expressions work in tab"
        or diag Dumper $res;

       $res = $chrome->eval('var x = {"foo": "bar"}; x')->get;
    is_deeply $res, {foo => 'bar'}, "Somewhat complex expressions work in tab"
        or diag Dumper $res;

	# Check that we can get sensible Chrome version information
	my $info = $chrome->getVersion->get;
	like $info->{product}, qr!^.*?/(\d+(?:\.\d+)+)$!, "We can retrieve a sensible browser version"
	    or diag Dumper $info;
});
