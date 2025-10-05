package # hide from CPAN indexer
    t::helper;
use strict;
use Test::More;
use File::Glob qw(bsd_glob);
use Config '%Config';
use File::Spec;
use Carp qw(croak);
use File::Temp 'tempdir';
use WWW::Mechanize::Chrome;
use Config;
use Time::HiRes 'sleep';

use Log::Log4perl ':easy';

delete $ENV{HTTP_PROXY};
delete $ENV{HTTPS_PROXY};
$ENV{PERL_FUTURE_DEBUG} = 1
    if not exists $ENV{PERL_FUTURE_DEBUG};

sub need_minimum_chrome_version {
    my( $version, @args ) = @_;
    $version =~ m!^(\d+)\.(\d+)\.(\d+)\.(\d+)$!
        or croak "Invalid version parameter '$version'";
    my( $need_maj, $need_min, $need_sub, $need_patch ) = ($1,$2,$3,$4);

    my $v = WWW::Mechanize::Chrome->chrome_version( @args );
    $v =~ m!/(\d+)\.(\d+)\.(\d+)\.(\d+)$!
        or die "Couldn't find version info from '$v'";
    my( $maj, $min, $sub, $patch ) = ($1,$2,$3,$4);
    if(    $maj < $need_maj
        or $maj == $need_maj and $min < $need_min
        or $maj == $need_maj and $min == $need_min and $sub < $need_sub
        or $maj == $need_maj and $min == $need_min and $sub == $need_sub and $patch < $need_patch
    ) {
        croak "Chrome $v is unsupported. Minimum required version is $version.";
    };
};

sub browser_instances {
    my ($filter) = @_;
    $filter ||= qr/^/;

    # (re)set the log level
    if (my $lv = $ENV{TEST_LOG_LEVEL}) {
        if( $lv eq 'trace' ) {
            Log::Log4perl->easy_init($TRACE)
        } elsif( $lv eq 'debug' ) {
            Log::Log4perl->easy_init($DEBUG)
        }
    }

    my @instances;

    if( $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE}) {
        push @instances, $ENV{TEST_WWW_MECHANIZE_CHROME_VERSIONS};

    } elsif( $ENV{TEST_WWW_MECHANIZE_CHROME_VERSIONS} ) {
        # add author tests with local versions
        my $spec = $ENV{TEST_WWW_MECHANIZE_CHROME_VERSIONS};
        push @instances, grep { -x } bsd_glob $spec;

    } elsif( $ENV{CHROME_BIN}) {
        push @instances, $ENV{ CHROME_BIN }
            if $ENV{ CHROME_BIN } and -x $ENV{ CHROME_BIN };

    } else {
        my ($default) = WWW::Mechanize::Chrome->find_executable();
        push @instances, $default
            if $default;
        my $spec = 'chrome-versions/*/{*/,}chrome' . $Config{_exe}; # sorry, likely a bad default
        push @instances, grep { -x } bsd_glob $spec;
    };

    # Consider filtering for unsupported Chrome versions here
    @instances = map { s!\\!/!g; $_ } # for Windows
                 grep { ($_ ||'') =~ /$filter/ } @instances;

    # Only use unique Chrome executables
    my %seen;
    @seen{ @instances } = 1 x @instances;

    # Well, we should do a nicer natural sort here
    @instances = sort {$a cmp $b} keys %seen;
};

sub default_unavailable {
    !scalar browser_instances
};

sub runtests {
    my ($browser_instance, $new_mech, $code, $test_count) = @_;
    if ($browser_instance) {
        note sprintf "Testing with %s",
            $browser_instance;
    };
    my $tempdir = tempdir( CLEANUP => 1 );
    my @launch;
    if( $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE} ) {
        my( $host, $port ) = split /:/, $ENV{TEST_WWW_MECHANIZE_CHROME_INSTANCE};
        @launch = ( host => $host,
                    port => $port,
                    reuse => 1,
                    new_tab => 1,
                  );
    } else {
        @launch = ( launch_exe => $browser_instance,
                    #port => $port,
                    data_directory => $tempdir,
                    headless => 1,
                  );
    };

    {
        my $mech = eval { $new_mech->(@launch) };
#warn sprintf "Launched pid %d", $mech->{pid};
        if( ! $mech ) {
            my $err = $@;
            SKIP: {
                skip "Couldn't create new object: $err", $test_count;
            };
            my $version = eval {
                WWW::Mechanize::Chrome->chrome_version(
                    launch_exe => $browser_instance
                );
            };
            diag sprintf "Failed on Chrome version '%s': %s", ($version || '(unknown)'), $err;
            return
        };

        note sprintf "Using Chrome version '%s'",
            $mech->chrome_version;

        # Run the user-supplied tests, making sure we don't keep a
        # reference to $mech around
        @_ = ($browser_instance, $mech);
    };

    # At least this process should've gone away
    #my $pid = $_[1]->{pid};
    goto &$code;
    #@_ = ();
    #kill 0 => $pid
    #    and die "Leftover process $pid!";
}

sub run_across_instances {
    #my ($instances, $new_mech, $test_count, $code) = @_;

    croak "No test count given"
        unless $_[2]; #$test_count;

    for my $browser_instance (@{$_[0]}) {
        runtests( $browser_instance, @_[1,3,2] );
        #undef $new_mech;
        #sleep 0.5 if @{$_[0]};
        # So the browser can shut down before we try to connect
        # to the new instance
    };
};

1;
