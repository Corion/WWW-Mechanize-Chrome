#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 5*@instances;
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

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 5, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my $html = $mech->content;
    like $html, qr!<html><head></head><body></body></html>!, "We can get the plain HTML";

    my $html2 = $mech->content( format => 'html' );
    is $html2, $html, "When asking for HTML explicitly, we get the same text";

    my $text = $mech->content( format => 'text' );
    is $text, '', "We can get the plain text";

    my $text2;
    my $lives = eval { $mech->content( format => 'bogus' ); 1 };
    ok !$lives, "A bogus content format raises an error";
});