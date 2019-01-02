#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;

use strict;
use Test::More;
use Cwd;
use URI;
use URI::file;
use File::Basename;
use File::Spec;
use File::Temp 'tempdir';
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 7*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);
my $server_url = $server->url;

t::helper::run_across_instances(\@instances, \&new_mech, 7, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    $mech->get_local('51-mech-links-nobase.html');

    my @found_links = $mech->links;
    # There is a FRAME tag, but FRAMES are exclusive elements
    # so Chrome ignores it while WWW::Mechanize picks it up
    # Also, links without a href= attribute don't get found by Chrome
    if (! is scalar @found_links, 5, 'All 5 links were found') {
        diag sprintf "%s => %s", $_->tag, $_->url
            for @found_links;
    };

    $mech->get_local('51-mech-links-base.html');

    @found_links = $mech->links;
    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and $1 < 60 ) {
            skip "Chrome before v60 recognizes some weird links", 3;
        } else {
            # Weirdo ISPs like frontier.com inject more links into pages that
            # resolve to non-existent domains
            my @wanted_links = grep { $_->url_abs =~ m!^\Qhttps://somewhere.example/\E! } @found_links;

            if( ! is scalar @wanted_links, 2, 'The two links were found') {
                diag $_->url for @found_links;
                diag $_->url_abs for @found_links;
                diag $server_url;
            };
            my $url = URI->new_abs($found_links[0]->url, $found_links[0]->base);
            is $url, 'https://somewhere.example/relative',
                'BASE tags get respected';
            $url = URI->new_abs($found_links[1]->url, $found_links[1]->base);
            is $url, 'https://somewhere.example/myiframe',
                'BASE tags get respected for iframes';
        };
    }

    # There is a FRAME tag, but FRAMES are exclusive elements
    # so Firefox ignores it while WWW::Mechanize picks it up
    my @frames = $mech->selector('frame');
    is @frames, 0, "FRAME tag"
        or diag $mech->content;

    @frames = $mech->selector('iframe');
    is @frames, 1, "IFRAME tag";
});

undef $server;