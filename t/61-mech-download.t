#!perl -w
use strict;
use Test::More;
use Cwd;
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
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 5*@instances;
};

my $d = tempdir;
sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        download_directory => $d,
        @_,
        #headless => 0,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 5, sub {

    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and $1 < 62 ) {
            skip "Chrome before v62 doesn't know about downloads...", 4;

        } elsif( $version =~ /\b(\d+)\.\d+\.(\d+)\b/ and ($1 >= 63 and $2 >= 3239)) {
            skip "Chrome before v63 build 3292 doesn't know about downloads anymore", 4;

        } elsif( $version =~ /\b(\d+)\b/ and $1 >= 64 ) {
            skip "Chrome after v63 doesn't tell us about downloads...", 4;

        } else {

            my ($site,$estatus) = ($server->download('mytest.txt'),200);
            my $res = $mech->get($site);
            isa_ok $res, 'HTTP::Response', "Response";
            ok $mech->success, "The download (always) succeeds";
            like $res->header('Content-Disposition'), qr/attachment;/, "We got a download response";

            $mech->sleep(2); # well, should be faster, but...
            ok -f "$d/mytest.txt", "File 'mytest.txt' was downloaded OK";
        };
    }
});

done_testing;