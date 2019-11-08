#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Chrome::DevToolsProtocol;
use WWW::Mechanize::Chrome; # for launching Chrome
use Log::Log4perl qw(:easy);

use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    my $chrome = WWW::Mechanize::Chrome->new(
        #transport => 'Chrome::DevToolsProtocol::Transport::AnyEvent',
        @_
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, 4, sub {
    my( $file, $mech ) = splice @_;
    my $chrome = $mech->driver;

    isa_ok $chrome, 'Chrome::DevToolsProtocol::Target';

    my $version = $chrome->version_info->get;
    note $version->{Browser};

    my @tabs = $chrome->getTargets()->get;
    cmp_ok 0+@tabs, '>', 0,
        "We have at least one open (empty) tab";

    my $new = $chrome->createTarget( url => 'about:blank' )->get;
    note "Created new tab $new->{targetId}";

    my @tabs2 = $chrome->getTargets()->get;
    cmp_ok 0+@tabs2, '>', 1,
        "We have at least two open (empty) tabs now";

    note "Closing tab";
    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and $1 == 61 ) {
            skip "Chrome v61 doesn't properly close tabs...", 1;

        } else {
            $chrome->transport->closeTarget( targetId => $new->{targetId} )->get;

            sleep 1; # need to give Chrome some time here to clean up its act?!

            my @tabs3;
            my $ok = eval { @tabs3 = $chrome->getTargets()->get; 1 };
            SKIP: {
                if( ! $ok ) {
                    skip $@, 1;
                };

                my @old_ids = grep { $_->{targetId} eq $new->{targetId} } @tabs3;
                if(! is 0+@old_ids, 0, "Our new tab was closed again") {
                    diag Dumper \@old_ids;
                };
            };
        }
    }

    undef $chrome;
});
