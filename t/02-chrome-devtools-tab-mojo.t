#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Chrome::DevToolsProtocol;
use WWW::Mechanize::Chrome; # for launching Chrome

use lib 'inc', '../inc', '.';
use t::helper;

my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    my $chrome = WWW::Mechanize::Chrome->new(
        log => sub {},
        transport => 'Chrome::DevToolsProtocol::Transport::Mojo',
        @_
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 4, sub {
    my( $file, $mech ) = splice @_;
    my $chrome = $mech->driver;

    isa_ok $chrome, 'Chrome::DevToolsProtocol';

    my $version = $chrome->version_info->get;
    diag $version->{Browser};

    my @tabs = $chrome->list_tabs()->get;
    cmp_ok 0+@tabs, '>', 0,
        "We have at least one open (empty) tab";

    my $new = $chrome->new_tab('about:blank')->get;
    diag "Created new tab $new->{id}";
        
    my @tabs2 = $chrome->list_tabs()->get;
    cmp_ok 0+@tabs2, '>', 1,
        "We have at least two open (empty) tabs now";
        
    $chrome->close_tab( $new )->get;
    sleep 1; # need to give Chrome some time here to clean up its act?!

    my @tabs3 = $chrome->list_tabs()->get;

    my @old_ids = grep { $_->{id} eq $new->{id} } @tabs3;
    if(! is 0+@old_ids, 0, "Our new tab was closed again") {
        diag Dumper \@old_ids;
    };
    
    undef $chrome;
});