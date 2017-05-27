#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use lib '.';

use t::helper;

my @tests = (
    [ 'mixi_jp_index.html', 'EUC-JP', qr/\x{30DF}\x{30AF}\x{30B7}\x{30A3}/ ],
    [ 'sophos_co_jp_index.html', 'SHIFT_JIS', qr/\x{30B0}\x{30ED}\x{30FC}\x{30D0}\x{30EB}/ ],
);
my $testcount = @tests;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

my %args;
sub new_mech {
    # Just keep these to pass the parameters to new instances
    if( ! keys %args ) {
        %args = @_;
    };
    #use Mojolicious;
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        %args,
    );
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    for (@tests) {
            my ($file,$encoding,$content_re) = @$_;
            $mech->get_local($file);
            is uc $mech->content_encoding, $encoding, "$file has encoding $encoding";
            diag length $mech->content;
            like $mech->content, $content_re, "Partial expression gets found in UTF-8 content";
    };
});