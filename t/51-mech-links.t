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
use Data::Dumper;

use WWW::Mechanize::Chrome;

use lib '.';

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 9;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
        #headless => 0,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;
    isa_ok $mech, 'WWW::Mechanize::Chrome';

    $mech->get_local('51-mech-links-nobase.html');

    my @found_links = $mech->links;
    # There is a FRAME tag, but FRAMES are exclusive elements
    # so Chrome ignores it while WWW::Mechanize picks it up
    if (! is scalar @found_links, 6, 'All 6 links were found') {
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

    $mech->get_local('html5.html');
    @found_links = map {[$_->url,$_->text]}
                   grep { $_->url } $mech->links;
    is_deeply \@found_links, [
        ['http://www.example.com/1', 'One'],
        ['http://www.example.com/5', 'Five'],
        ['http://www.example.com/7', 'Seven'],
    ], "We parse nasty HTML5"
        or diag Dumper \@found_links;

    {
        # https://bugs.chromium.org/p/chromium/issues/detail?id=1080560
        local $TODO = "Chrome bug 1080560, Chrome DevTools don't implement XML parsing";
        my $file = 't/xhtml.xhtml';
        my $html = do { open my $fh, '<', $file or die "$file: $!"; local $/; <$fh> };
        $mech->update_html($html);
        #$mech->get_local('xhtml.xhtml'); # this still fails
        @found_links = map {[$_->url,$_->text]}
                   grep { $_->url } $mech->links;
        if(! is_deeply \@found_links, [
            ['http://www.example.com/1', 'One'],
            ['http://www.example.com/5', 'Five'],
            ['http://www.example.com/7', 'Seven'],
        ], "We parse nasty XHTML") {
            diag Dumper \@found_links;
            diag $mech->uri;
            diag $mech->ct;
            #diag $mech->content;
        };
    };
});
