package # hide from CPAN indexer
    t::helper;
use strict;
use Test::More;
use File::Glob qw(bsd_glob);
use Config '%Config';
use File::Spec;
use Carp qw(croak);

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

    # add author tests with local versions
    my $spec = $ENV{TEST_WWW_MECHANIZE_CHROMES_VERSIONS}
             || 'chrome-versions/*/{*/,}chrome*'; # sorry, likely a bad default
    push @instances, sort {$a cmp $b} grep { -x } bsd_glob $spec;

    # Consider filtering for unsupported Chrome versions here

    grep { ($_ ||'') =~ /$filter/ } @instances;
};

sub default_unavailable {
    !scalar browser_instances
};

sub run_across_instances {
    my ($instances, $port, $new_mech, $test_count, $code) = @_;

    croak "No test count given"
        unless $test_count;

    for my $browser_instance (@$instances) {
        if ($browser_instance) {
            diag sprintf "Testing with %s",
                $browser_instance;
        };
        my @launch = $browser_instance
                   ? ( launch_exe => $browser_instance,
                       port => $port )
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
            next
        };

        diag sprintf "Chrome version '%s'",
            $mech->chrome_version;

        # Run the user-supplied tests
        $code->($browser_instance, $mech);

        # Quit in 500ms, so we have time to shut our socket down
        undef $mech;
        sleep 2; # So the browser can shut down before we try to connect
        # to the new instance
    };
};

1;