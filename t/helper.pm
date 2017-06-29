package # hide from CPAN indexer
    t::helper;
use strict;
use Test::More;
use File::Glob qw(bsd_glob);
use Config '%Config';
use File::Spec;
use Carp qw(croak);
use File::Temp 'tempdir';

delete $ENV{HTTP_PROXY};
delete $ENV{HTTPS_PROXY};

sub browser_instances {
    my ($filter) = @_;
    $filter ||= qr/^/;
    my @instances;
    # default Chrome instance
    my ($default)=
        map { my $exe= File::Spec->catfile($_,"chrome$Config{_exe}");
              -x $exe ? $exe : ()
            } File::Spec->path();
    push @instances, $default
        if $default;

    push @instances, $ENV{ CHROME_BIN }
        if $ENV{ CHROME_BIN } and -x $ENV{ CHROME_BIN };

    # add author tests with local versions
    my $spec = $ENV{TEST_WWW_MECHANIZE_CHROMES_VERSIONS}
             || 'chrome-versions/*/{*/,}chrome*'; # sorry, likely a bad default
    push @instances, grep { -x } bsd_glob $spec;

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

my @cleanup_directories;
sub runtests {
    my ($browser_instance,$port, $new_mech, $code, $test_count) = @_;
    if ($browser_instance) {
        diag sprintf "Testing with %s",
            $browser_instance;
    };
    my $tempdir = tempdir();
    push @cleanup_directories, $tempdir;
    my @launch = $browser_instance
               ? ( launch_exe => $browser_instance,
                   port => $port,
                   data_directory => $tempdir,
                   #incognito => 1,
                 )
               : ();

    my $mech = eval { $new_mech->(@launch) };

    if( ! $mech ) {
        SKIP: {
            skip "Couldn't create new object: $@", $test_count;
        };
        my $version = eval {
            WWW::Mechanize::Chrome::chrome_version({
                launch_exe => $browser_instance
            });
        };
        diag sprintf "Chrome version '%s'", $version;
        return
    };

    diag sprintf "Chrome version '%s'",
        $mech->chrome_version;

    # Run the user-supplied tests, making sure we don't keep a
    # reference to $mech around
    @_ = ($browser_instance, $mech);
    undef $mech;
    
    goto &$code;
}
END {
    File::Path::rmtree($_, 0) for @cleanup_directories;
}

sub run_across_instances {
    my ($instances, $port, $new_mech, $test_count, $code) = @_;

    croak "No test count given"
        unless $test_count;

    for my $browser_instance (@$instances) {
        runtests( $browser_instance,$port, $new_mech, $code, $test_count );
        sleep 1; # So the browser can shut down before we try to connect
        # to the new instance
    };
};

1;
