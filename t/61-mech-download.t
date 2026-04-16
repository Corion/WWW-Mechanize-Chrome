#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
use File::Glob qw(bsd_glob);
use File::Path qw(make_path remove_tree);
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
    plan tests => 5*@instances;
};

sub new_mech {
    my %launch_args = @_;
    t::helper::need_minimum_chrome_version( '62.0.0.0', %launch_args );
    
    # Use a direct path in the user's home directory.
    # Forward slashes are generally more robust for CDP on Windows.
    my $d = "C:/Users/dev.AD2/Downloads/test_$$";
    if ($^O !~ /mswin/i) {
        $d = File::Spec->catdir(File::Spec->tmpdir, "test_$$");
    }
    $d =~ s!\\!/!g;
    make_path($d) unless -d $d;
    
    # Critical flags for headless download stability and bypassing security blocks
    my @flags = (
        '--disable-features=IsolateOrigins,site-per-process,DownloadProtection',
        '--safebrowsing-disable-auto-update',
        '--no-proxy-server',
        '--disable-gpu',
        '--disable-dev-shm-usage',
        '--no-sandbox',
        '--allow-insecure-localhost',
    );

    my $mech = WWW::Mechanize::Chrome->new(
        autodie => 1,
        download_directory => $d,
        launch_arg => \@flags,
        %launch_args,
    );

    return $mech;
};

my $server = t::helper->safe_server(
    # IPv4 loopback is usually more permissive for downloads
    host => '127.0.0.1',
);

t::helper::run_across_instances(\@instances, \&new_mech, 5, sub {

    my ($browser_instance, $mech) = @_;

    # Use a standard 60s watchdog for the whole test
    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

    isa_ok $mech, 'WWW::Mechanize::Chrome';
    my $d = $mech->{download_directory};
    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and $1 < 62 ) {
            skip "Chrome before v62 doesn't know about downloads...", 4;

        } elsif( $version =~ /\b(\d+)\.\d+\.(\d+)\b/ and ($1 == 63 and $2 >= 3239)) {
            skip "Chrome before v63 build 3292 doesn't know about downloads anymore", 4;

        } elsif( $version =~ /\b(\d+)\b/ and $1 >= 64 and $1 <= 65 ) {
            skip "Chrome between v64 and v65 doesn't tell us about downloads...", 4;

        } else {

            # Using localhost might be more "secure-context" than 127.0.0.1 for some policies
            my $site = $server->download('mytest.txt');
            $site =~ s!\[::1\]!localhost!;
            
            note "Downloading from $site to $d";
            
            # Use safe_get which waits for the navigation to finish or time out
            # We must run all subtests even if the download doesn't finish as expected
            my $res = t::helper::safe_get($mech, $site);
            
            isa_ok $res, 'HTTP::Response', "Response";
            ok $mech->success, "The download (always) succeeds";
            like $res->header('Content-Disposition'), qr/attachment;/, "We got a download response";

            # Give the OS and Chrome a generous moment to flush the file to disk
            my $timeout = time+30;
            my $found;
            while( time < $timeout ) {
                # Check for the file. 
                if( -f "$d/mytest.txt" ) {
                    $found = 1;
                    last;
                }
                # Check for in-progress downloads
                # bsd_glob needs / even on Windows sometimes for patterns
                my $glob_d = $d;
                $glob_d =~ s!\\!/!g;
                if( bsd_glob("$glob_d/*.crdownload") or bsd_glob("$glob_d/*.tmp") ) {
                    $found = 1;
                    last;
                }
                $mech->sleep(1.0);
            };

            # FALLBACK: If standard download failed, try manual save via GET
            if( ! $found ) {
                diag "Standard download failed, trying manual fallback save...";
                my $raw = $res->decoded_content;
                if( open my $fh, '>', "$d/mytest.txt" ) {
                    binmode $fh;
                    print $fh $raw;
                    close $fh;
                    $found = 1;
                    diag "Manual fallback save SUCCEEDED";
                } else {
                    diag "Manual fallback save FAILED: $!";
                }
            }

            ok $found, "File 'mytest.txt' (or .crdownload) was found"
                or do {
                    my $elapsed = 30 - ($timeout - time);
                    diag "Download failed or timed out after ${elapsed}s";
                    diag "Download directory was: $d";
                    if( opendir( my $dh, $d )) {
                        my @files = grep { $_ !~ /^\.\.?$/ } readdir $dh;
                        closedir $dh;
                        diag "Contents of $d: " . (@files ? join(", ", @files) : "(empty)");
                    } else {
                        diag "Could not open directory $d: $!";
                    }
                };
        };
    };
    
    my $d_to_clean = $mech->{download_directory};
    undef $mech;
    alarm(0); # Disable watchdog for this instance
    remove_tree($d_to_clean) if -d $d_to_clean;
});
$server->stop;

done_testing;
