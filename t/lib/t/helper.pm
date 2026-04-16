package # hide from CPAN indexer
    t::helper;

=head1 NAME

t::helper - Internal test helper for WWW::Mechanize::Chrome

=head1 SYNOPSIS

    use t::helper;

    # Set a 30-second watchdog
    t::helper::set_watchdog($t::helper::is_slow ? 180 : 30);

    # Get available Chrome instances
    my @instances = t::helper::browser_instances();

    # Run tests across all instances
    t::helper::run_across_instances(\@instances, \&new_mech, $test_count, sub {
        my ($instance, $mech) = @_;

        # Use safe wrappers with integrated timeouts
        t::helper::safe_get($mech, 'http://localhost/test');
        my $content = t::helper::safe_content($mech);
    });

=head1 DESCRIPTION

This module provides common utility functions for the WWW::Mechanize::Chrome
test suite. It is designed to handle platform-specific quirks (especially on
Windows Server), manage process cleanup, and provide "safe" wrappers around
core library methods to prevent tests from hanging indefinitely.

The module also monkey-patches C<WWW::Mechanize::Chrome> during testing to
improve PID tracking and ensure more aggressive process termination via SIGKILL.

=cut

use strict;
use Test::More;
use File::Glob qw(bsd_glob);
use Config '%Config';
use File::Spec;
use Carp qw(croak);
use File::Temp 'tempdir';
use WWW::Mechanize::Chrome;
use Test::HTTP::LocalServer;
use Config;
use Time::HiRes qw(sleep time);
use POSIX qw(:sys_wait_h);
use IO::Socket::INET;

use Log::Log4perl ':easy';

delete $ENV{HTTP_PROXY};
delete $ENV{HTTPS_PROXY};
$ENV{PERL_FUTURE_DEBUG} = 1
    if not exists $ENV{PERL_FUTURE_DEBUG};

# Global PID tracking for fail-safe cleanup
our %all_spawned_pids;
our $is_slow = ($^O =~ /mswin/i or $ENV{TEST_SLOW});
{
    my $org_new = \&WWW::Mechanize::Chrome::new;
    no warnings 'redefine';
    *WWW::Mechanize::Chrome::new = sub {
        my $self = $org_new->(@_);
        if (ref $self && $self->{pid}) {
            for my $pid ($self->{pid}->@*) {
                $all_spawned_pids{$pid} = 1 if $pid;
            }
        }
        return $self;
    };

    # Override kill_child to be more aggressive and non-blocking in tests.
    # This prevents hangs during the cleanup phase of tests, especially with
    # modern Chromium versions that may not exit promptly on SIGTERM.
    *WWW::Mechanize::Chrome::kill_child = sub {
        my ($self, $signal, $pids, $wait_file) = @_;
        return unless $pids;

        my @p = ref $pids eq 'ARRAY' ? @$pids : ($pids);

        for my $pid (@p) {
            next unless $pid && kill(0, $pid);

            # Use SIGKILL in tests to ensure swift termination and avoid hangs
            kill('KILL', $pid);

            # Non-blocking wait with a short timeout
            my $timeout = Time::HiRes::time() + 2;
            while (Time::HiRes::time() < $timeout) {
                my $res = waitpid($pid, WNOHANG);
                last if $res == -1 || $res == $pid;
                Time::HiRes::sleep(0.1);
            }

            delete $all_spawned_pids{$pid};
        }
        return;
    };

}

END {
    # Final fail-safe cleanup of all PIDs spawned during this test process
    for my $pid (keys %all_spawned_pids) {
        if ($pid && kill(0, $pid)) {
            kill('KILL', $pid);
            waitpid($pid, WNOHANG);
        }
    }
}

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
    return;
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
    return @instances;
};

sub default_unavailable {
    my @instances = browser_instances();
    if (!@instances) {
        $@ = "No Chrome executables found in PATH or standard locations.";
        return 1;
    }
    return 0;
};

sub runtests {
    my ($browser_instance, $new_mech, $code, $test_count) = @_;
    #if ($browser_instance) {
    #    note sprintf 'Testing with %s',
    #        $browser_instance;
    #};
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
            return;
        };

        note sprintf "Using Chrome version '%s'",
            $mech->chrome_version;

        # Run the user-supplied tests, making sure we don't keep a
        # reference to $mech around
        @_ = ($browser_instance, $mech);
    };

    # Ensure stack frame is cleared to allow proper destruction
    goto &$code;
}

sub run_across_instances {
    #my ($instances, $new_mech, $test_count, $code) = @_;

    croak 'No test count given'
        unless $_[2]; #$test_count;

    for my $browser_instance (@{$_[0]}) {
        runtests( $browser_instance, @_[1,3,2] );
    };
    return;
};

sub _safe_get {
    my ($f, $start, $label) = @_;
    my $wantarray = wantarray;
    my @res = eval { $f->get };
    my $err = $@;
    my $elapsed = Time::HiRes::time() - $start;
    if ($err) {
        Test::More::note(sprintf('%s failed after %.3fs: %s', $label, $elapsed, $err));
        die $err;
    }
    if ($elapsed > 0.1) {
        Test::More::note(sprintf('%s took %.3fs', $label, $elapsed));
    }
    return $wantarray ? @res : $res[0];
}

sub safe_xpath {
    my ($mech, $query, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 15 : 5);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->xpath_future($query, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during xpath search for $query") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('xpath("%s")', $query));
}

sub safe_sleep {
    my ($mech, $seconds) = @_;
    my $start = Time::HiRes::time();
    $mech->sleep_future($seconds)->get;
    my $elapsed = Time::HiRes::time() - $start;
    if ($elapsed > 0.1) {
        Test::More::note(sprintf('sleep(%.3fs)', $seconds));
    }
}

sub safe_current_form {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 90 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->current_form_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during current_form retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('current_form()'));
}

sub safe_get_attribute {
    my ($mech, $node, $attr, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 90 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $node->get_attribute_future($attr, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during get_attribute $attr") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('get_attribute("%s")', $attr));
}

sub safe_objectId {
    my ($mech, $node, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 90 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $node->objectId_future();
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during objectId retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('objectId()'));
}

sub safe_get {
    my ($mech, $url, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->get_future($url, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during navigation to $url") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('get("%s")', $url));
}

sub safe_get_local {
    my ($mech, $htmlfile, @args) = @_;
    my %options;
    if (scalar @args == 1 and ref $args[0] eq 'HASH') {
        %options = %{shift @args};
    } else {
        %options = @args;
    }
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->get_local_future($htmlfile, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during navigation to $htmlfile") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('get_local("%s")', $htmlfile));
}

sub safe_value {
    my ($mech, @args) = @_;
    my %options;
    if (ref $args[-1] eq 'HASH') {
        %options = %{pop @args};
    }
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 5);
    my $name = shift @args;
    my $index = shift @args;

    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f;
    if (defined $index) {
        $call_f = $mech->value_future($name, $index, %options);
    } else {
        $call_f = $mech->value_future($name, %options);
    }
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during value retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('value("%s")', $name));
}

sub safe_field {
    my ($mech, $name, $value, @args) = @_;
    my %options;
    if (@args and ref $args[-1] eq 'HASH') {
        %options = %{pop @args};
    }
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 5);
    my $index = shift @args;

    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    my $call_f = $mech->field_future($name, $value, $index, @args);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during field setting") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('field("%s")', $name));
}

sub safe_set_fields {
    my ($mech, %fields) = @_;
    my $timeout = ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->set_fields_future(%fields);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during set_fields") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('set_fields'));
}

sub safe_content {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->content_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during content retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('content()'));
}

sub safe_decoded_content {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->decoded_content_future();
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during decoded_content retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('decoded_content()'));
}

sub safe_text {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->text_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during text retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('text()'));
}

sub safe_render_content {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 60 : 30); # Rendering can be slow
    my $start = Time::HiRes::time();
    my $call_f = $mech->render_content_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during render_content") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('render_content()'));
}

sub safe_content_as_png {
    my ($mech, @args) = @_;
    my ($rect, $target, %options);
    if( @args == 1 and ref $args[0] eq 'HASH' ) {
        if (exists $args[0]->{left} or exists $args[0]->{top} or exists $args[0]->{width} or exists $args[0]->{height}) {
            $rect = $args[0];
        } else {
            %options = %{ $args[0] };
        }
    } elsif( @args % 2 == 0 and @args > 0 and not ref $args[0] ) {
        %options = @args;
    } else {
        ($rect, $target, %options) = @args;
    };
    $rect //= {};
    $target //= {};

    my $timeout = delete $options{timeout} || ($is_slow ? 60 : 30);
    my $start = Time::HiRes::time();
    my $call_f = $mech->content_as_png_future($rect, $target, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during content_as_png") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('content_as_png()'));
}

sub safe_content_as_pdf {
    my ($mech, @args) = @_;
    my ($rect, $target, %options);
    if( @args == 1 and ref $args[0] eq 'HASH' ) {
        if (exists $args[0]->{left} or exists $args[0]->{top} or exists $args[0]->{width} or exists $args[0]->{height}) {
            $rect = $args[0];
        } else {
            %options = %{ $args[0] };
        }
    } elsif( @args % 2 == 0 and @args > 0 and not ref $args[0] ) {
        %options = @args;
    } else {
        ($rect, $target, %options) = @args;
    };
    $rect //= {};
    $target //= {};

    my $timeout = delete $options{timeout} || ($is_slow ? 60 : 30);
    my $start = Time::HiRes::time();
    my $call_f = $mech->content_as_pdf_future($rect, $target, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during content_as_pdf") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('content_as_pdf()'));
}

sub safe_update_html {
    my ($mech, $html, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->update_html_future($html);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during update_html") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('update_html()'));
}

sub safe_wait_for_ready {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    
    my $call_f = repeat {
        $mech->eval_future("document.readyState")->then(sub {
            my ($res) = @_;
            my ($state, $type) = $mech->_process_eval_result($res);
            if ($state eq 'complete') {
                return Future->done(1);
            } else {
                return $mech->sleep_future(0.2)->then(sub { Future->done(undef) });
            }
        });
    } while => sub {
        my ($f) = @_;
        ! $f->get
    };

    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during wait_for_ready") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('wait_for_ready()'));
}

sub safe_is_visible {
    my ($mech, @args) = @_;
    my %options;
    if( @args == 1 and ref $args[0] eq 'HASH' ) {
        %options = %{ $args[0] };
    } elsif( @args % 2 == 0 and @args > 0 and not ref $args[0] ) {
        %options = @args;
    }
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->is_visible_future(@args);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during is_visible") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('is_visible()'));
}

sub safe_wait_until_invisible {
    my ($mech, @args) = @_;
    my $start = Time::HiRes::time();
    my $f = $mech->wait_until_invisible_future(@args);
    return _safe_get($f, $start, sprintf('wait_until_invisible()'));
}

sub safe_wait_until_visible {
    my ($mech, @args) = @_;
    my $start = Time::HiRes::time();
    my $f = $mech->wait_until_visible_future(@args);
    return _safe_get($f, $start, sprintf('wait_until_visible()'));
}

sub safe_follow_link {
    my ($mech, @args) = @_;
    my %options;
    if( @args == 1 and ref $args[0] eq 'HASH' ) {
        %options = %{ $args[0] };
    } elsif( @args % 2 == 0 and @args > 0 and not ref $args[0] ) {
        %options = @args;
    }
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->follow_link_future(@args);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during follow_link") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('follow_link()'));
}

sub safe_click {
    my ($mech, $name, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->click_future($name, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during click") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('click()'));
}

sub safe_submit {
    my ($mech, $form, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->submit_future($form);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during submit") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('submit()'));
}

sub safe_tick {
    my ($mech, @args) = @_;
    my ($name, $value, $set, %options);
    if( @args == 1 and ref $args[0] eq 'HASH' ) {
        %options = %{ $args[0] };
    } elsif( @args % 2 == 0 and @args > 0 and not ref $args[0] and $args[0] =~ /^(?:timeout|wantarray)/ ) {
        %options = @args;
    } else {
        ($name, $value, $set, %options) = @args;
    };
    $set //= 1;

    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->tick_future($name, $value, $set);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during tick") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('tick()'));
}

sub safe_untick {
    my ($mech, @args) = @_;
    my ($name, $value, %options);
    if( @args == 1 and ref $args[0] eq 'HASH' ) {
        %options = %{ $args[0] };
    } elsif( @args % 2 == 0 and @args > 0 and not ref $args[0] and $args[0] =~ /^(?:timeout|wantarray)/ ) {
        %options = @args;
    } else {
        ($name, $value, %options) = @args;
    };

    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->untick_future($name, $value);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during untick") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('untick()'));
}

sub safe_selector {
    my ($mech, $query, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->selector_future($query, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during selector search for $query") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('selector("%s")', $query));
}

sub safe_eval_in_page {
    my ($mech, $js, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->eval_in_page_future($js, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during eval_in_page") });
    my $f = Future->wait_any($call_f, $timeout_f); my $result = _safe_get($f, $start, sprintf('eval_in_page()'));
    if ($wantarray) {
        return $mech->_process_eval_result($result);
    } else {
        my ($val, $type) = $mech->_process_eval_result($result);
        return $val;
    }
}

sub safe_eval {
    my ($mech, $js, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->eval_future($js, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during eval") });
    my $f = Future->wait_any($call_f, $timeout_f); my $result = _safe_get($f, $start, sprintf('eval()'));
    if ($wantarray) {
        return $mech->_process_eval_result($result);
    } else {
        my ($val, $type) = $mech->_process_eval_result($result);
        return $val;
    }
}

sub safe_callFunctionOn {
    my ($mech, $js, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->callFunctionOn_future($js, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during callFunctionOn") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('callFunctionOn()'));
}

sub safe_form_name {
    my ($mech, $name, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->form_name_future($name, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during form_name") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('form_name()'));
}

sub safe_form_id {
    my ($mech, $id, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->form_id_future($id, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during form_id") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('form_id()'));
}

sub safe_form_number {
    my ($mech, $number, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $call_f = $mech->form_number_future($number, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during form_number") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('form_number()'));
}

sub safe_form_with_fields {
    my ($mech, @fields) = @_;
    my %options;
    if (ref $fields[0] eq 'HASH') {
        %options = %{shift @fields};
    }
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->form_with_fields_future(@fields, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during form_with_fields") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('form_with_fields()'));
}

sub safe_submit_form {
    my ($mech, @args) = @_;
    my %options;
    if (ref $args[0] eq 'HASH') {
        %options = %{$args[0]};
    } else {
        %options = @args;
    }
    my $timeout = delete $options{timeout} || 20;
    my $start = Time::HiRes::time();
    my $call_f = $mech->submit_form_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during submit_form") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('submit_form()'));
}

sub safe_infinite_scroll {
    my ($mech, $wait, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 60 : 30);
    my $start = Time::HiRes::time();
    my $call_f = $mech->infinite_scroll_future($wait);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during infinite_scroll") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('infinite_scroll()'));
}

sub safe_reload {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->reload_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during reload") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('reload()'));
}

sub safe_back {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->back_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during back") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('back()'));
}

sub safe_forward {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->forward_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during forward") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('forward()'));
}

sub safe_click_button {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $call_f = $mech->click_button_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during click_button") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('click_button()'));
}

sub safe_by_id {
    my ($mech, $id, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 10);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->by_id_future($id, %options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during by_id search for $id") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('by_id("%s")', $id));
}

sub safe_find_link_dom {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->find_link_dom_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during find_link_dom") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('find_link_dom()'));
}

sub safe_forms {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->forms_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during forms retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('forms()'));
}

sub safe_find_all_links {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->find_all_links_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during find_all_links") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('find_all_links()'));
}

sub safe_links {
    my ($mech, %options) = @_;
    my $timeout = delete $options{timeout} || ($is_slow ? 180 : 15);
    my $start = Time::HiRes::time();
    my $wantarray = wantarray;
    $options{ wantarray } = $wantarray;
    my $call_f = $mech->links_future(%options);
    my $timeout_f = $mech->sleep_future($timeout)->then(sub { Future->fail("Timeout during links retrieval") });
    my $f = Future->wait_any($call_f, $timeout_f); return _safe_get($f, $start, sprintf('links()'));
}

sub safe_server {
    my ($self, %options) = @_;
    my $retries = 3;
    my $server;
    my $err;
    while ($retries--) {
        $server = eval { Test::HTTP::LocalServer->spawn(%options) };
        if ($server && eval { $server->url }) {
            return $server;
        }
        $err = $@ || "Unknown error";
        Test::More::diag("Test::HTTP::LocalServer spawn failed ($err), retrying ($retries left)...") if $retries > 0;
        sleep 1;
    }
    die "Failed to spawn Test::HTTP::LocalServer after 3 retries: $err";
}

our $watchdog_socket;
sub set_watchdog {
    my ($timeout_s) = @_;
    my $name = (caller(1))[3] || 'Test';
    my $target_pid = $$;

    $SIG{ALRM} = sub { 
        my $msg = "$name timed out after ${timeout_s}s!";
        print STDERR "\n$msg (ALRM)\n";
        CORE::exit(1);
    };

    if( $^O =~ /mswin/i ) {
        # Create a socket for self-cancelling watchdog
        my $listener = IO::Socket::INET->new(
            LocalAddr => '127.0.0.1',
            LocalPort => 0,
            Listen    => 1,
            Reuse     => 1,
        ) or die "Could not create watchdog socket: $!";
        my $port = $listener->sockport;
        
        # Spawn the killer. 
        # 1. Connects to the port.
        # 2. Sets its own alarm.
        # 3. Blocks on read. 
        # If main process dies, killer's read returns 0 and it exits.
        # If killer's alarm hits, it kills the main process.
        
        my $script = <<PERL;
\$SIG{ALRM} = sub {
    print STDERR "\\nWatchdog firing for $target_pid after $timeout_s s\\n";
    system(q{ssh -i C:/Users/dev.AD2/.ssh/id_rsa -o StrictHostKeyChecking=no administrator\@100.64.79.66 "taskkill /F /T /PID $target_pid"});
    kill(9, $target_pid);
    exit;
};
alarm($timeout_s);
require IO::Socket::INET;
my \$s = IO::Socket::INET->new(PeerAddr=>'127.0.0.1', PeerPort=>$port);
if (\$s) {
    \$s->read(my \$buf, 1);
}
exit;
PERL

        if (system(1, 'perl', '-e', $script)) {
            # Killer spawned
        }
        $watchdog_socket = $listener; # Keep it alive to keep the connection
        
        Test::More::note("Watchdog enabled ($timeout_s s) for PID $target_pid (socket-based)");
        alarm($timeout_s);
    } else {
        # Use ualarm for sub-second precision if needed, but here we take seconds
        Time::HiRes::ualarm($timeout_s * 1_000_000);
    }
}

=head1 FUNCTIONS

=head2 C<set_watchdog( $timeout_seconds )>

Sets a process-level watchdog timer. If the test process exceeds this timeout, it
will be terminated. On Windows Server (C<AD2>), it spawns a background process
that uses C<taskkill> via SSH to ensure the entire Chrome process tree is cleaned up.

=head2 C<browser_instances( $filter_regex )>

Returns a list of Chrome executable paths to test against. It respects the
C<CHROME_BIN> and C<TEST_WWW_MECHANIZE_CHROME_VERSIONS> environment variables.

=head2 C<safe_server( %options )>

A robust wrapper around C<Test::HTTP::LocalServer-E<gt>spawn>. It retries
spawning the server up to 3 times on failure, which is useful on Windows.

=head2 C<safe_get( $mech, $url, %options )>

A non-blocking wrapper around C<get_future> that includes a default 10-second
timeout and timing diagnostics.

=head2 C<safe_xpath( $mech, $query, %options )>

A non-blocking wrapper around C<xpath_future> that includes a default 5-second
timeout.

=head2 C<safe_field( $mech, $name, $value, @args )>

A non-blocking wrapper around C<field_future> that includes a 5-second timeout.

=head2 C<safe_value( $mech, @args )>

A non-blocking wrapper around C<get_set_value_future> with a 5-second timeout.

=head2 C<safe_set_fields( $mech, %fields )>

A non-blocking wrapper around C<set_fields_future> with a 15-second timeout.

=head2 C<safe_content( $mech, %options )>

A non-blocking wrapper around C<content_future> with a 10-second timeout.

=head2 C<safe_decoded_content( $mech, %options )>

A non-blocking wrapper around C<decoded_content_future> with a 10-second timeout.

=head2 C<safe_render_content( $mech, %options )>

A non-blocking wrapper around C<render_content_future> with a 30-second timeout.

=head2 C<safe_content_as_png( $mech, %options )>

A non-blocking wrapper around C<content_as_png_future> with a 30-second timeout.

=head2 C<safe_content_as_pdf( $mech, %options )>

A non-blocking wrapper around C<content_as_pdf_future> with a 30-second timeout.

=head2 C<safe_update_html( $mech, $html, %options )>

A non-blocking wrapper around C<update_html_future> with a 10-second timeout.

=cut

1;
