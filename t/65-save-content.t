#!perl -w
use strict;
use Test::More;
use Data::Dumper;
use Log::Log4perl qw(:easy);
use File::Temp 'tempdir';
use File::Basename 'dirname';

use WWW::Mechanize::Chrome;
use lib '.';

use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();

my $testcount = 1+ 4*2;
if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} elsif( $ENV{ TEST_WWW_MECHANIZE_CHROME_INSTANCE}) {
    plan skip_all => "Test doesn't play well with reattached Chrome sessions";
    exit

} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1,
);

my @test_urls = ($server->url, WWW::Mechanize::Chrome->_local_url( '52-iframeset.html' ));

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;
    my $version = $mech->chrome_version;

    if( $version =~ /\b(\d+)\b/ and $1 < 60 ) {
        SKIP: {
            skip "Chrome before v60 doesn't list all frame parts", $testcount;
        };
        return
    };

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    for my $base_url (@test_urls) {

    my $topdir = tempdir( CLEANUP => 1 );

    #my %r = $mech->saveResources_future(
    #    target_file => "test page.html"
    #)->get();
    #is_deeply \%r, {
    #    $server->url => 'test page.html',
    #}, "We return a map of the saved files"
    #    or diag Dumper \%r;

    #my $base_url = 'https://corion.net/econsole/';
    #my $base_url = 'https://corion.net/';
    $mech->get($base_url);
    my $page_file = File::Spec->catfile($topdir, "test page.html");
    my $r = $mech->saveResources_future(
        target_file => $page_file,
        wanted      => sub { $_[0]->{url} =~ /^(https?|file):/i },
    )->get();

    ok -f $page_file, "Top HTML file exists ($page_file)";

    is $r->{ $base_url }, $page_file,
        "We save the URL under the top HTML filename"
        or diag Dumper $r;
    if( -f $page_file ) {
        local $/;
        open my $fh, '<', $page_file
            or die "Couldn't read temp file '$page_file': $!";
        my $html = <$fh>;
        like $html, qr/<html\b/i, "... and it's HTML";
    } else {
        SKIP: {
            skip "Didn't write the file", 1;
        };
    };

    # Check that we save all the additional resources below $topdir
    # even though none was specified
    my @files_not_in_base_dir = map  { $_ => $r->{$_} }
                                grep { dirname($r->{$_}) ne File::Spec->catdir($topdir, "test page files") } keys %$r;
    is_deeply \@files_not_in_base_dir, [$base_url, File::Spec->catfile($topdir, "test page.html")],
        "All additional files get saved below our directory '$topdir/test page files'"
        or diag Dumper $r, \@files_not_in_base_dir;

    };

});
$server->stop;

