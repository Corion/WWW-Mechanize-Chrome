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


if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} elsif(! eval {
    require Test::Memory::Cycle;
    1;
}) {
    plan skip_all => "$@";
    exit
} else {
    plan tests => 8*@instances;
};

sub new_mech {
    my $chrome = WWW::Mechanize::Chrome->new(
        @_,
        autoclose_tab => 0,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 8, sub {
    my( $file, $mech ) = splice @_;
    my $chrome = $mech->driver;
    #undef $mech;

    isa_ok $chrome, 'Chrome::DevToolsProtocol::Target';
    Test::Memory::Cycle::memory_cycle_ok($chrome, "We have no cycles at the start");

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
        isn::t $tab, undef, "Attached to tab '$target_tab->{title}'";
    };

    my $res = $chrome->eval('1+1')->get;
    is $res, 2, "Simple expressions work in tab"
        or diag Dumper $res;

       $res = $chrome->eval('var x = {"foo": "bar"}; x')->get;
    is_deeply $res, {foo => 'bar'}, "Somewhat complex expressions work in tab"
        or diag Dumper $res;

    Test::Memory::Cycle::memory_cycle_ok($chrome, "We have no cycles at the end");
});
