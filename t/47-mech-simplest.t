#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;

my $mech = eval { WWW::Mechanize::Chrome->new( 
    autodie => 0,
    log => sub {},
)};

if (! $mech) {
    my $err = $@;
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 1;
};

isa_ok $mech, 'WWW::Mechanize::Chrome';
