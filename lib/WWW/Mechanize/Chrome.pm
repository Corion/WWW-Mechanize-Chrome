package WWW::Mechanize::Chrome;
use strict;
use warnings;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';
use File::Spec;
use HTTP::Response;
use HTTP::Headers;
use Scalar::Util qw( blessed weaken);
use File::Basename;
use Carp qw(croak carp);
use WWW::Mechanize::Link;
use IO::Socket::INET;
use Chrome::DevToolsProtocol;
use WWW::Mechanize::Chrome::Node;
use JSON;
use MIME::Base64 'decode_base64';
use Data::Dumper;
use Time::HiRes qw(usleep);
use Storable 'dclone';
use HTML::Selector::XPath 'selector_to_xpath';
use HTTP::Cookies::ChromeDevTools;

our $VERSION = '0.35';
our @CARP_NOT;

=encoding utf-8

=head1 NAME

WWW::Mechanize::Chrome - automate the Chrome browser

=head1 SYNOPSIS

  use Log::Log4perl qw(:easy);
  use WWW::Mechanize::Chrome;

  Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
  my $mech = WWW::Mechanize::Chrome->new();
  $mech->get('https://google.com');

  $mech->eval_in_page('alert("Hello Chrome")');
  my $png = $mech->content_as_png();

A collection of other L<Examples|WWW::Mechanize::Chrome::Examples> is available
to help you get started.

=head1 DESCRIPTION

Like L<WWW::Mechanize>, this module automates web browsing with a Perl object.
Fetching and rendering of web pages is delegated to the Chrome (or Chromium)
browser by starting an instance of the browser and controlling it with L<Chrome
DevTools|https://developers.google.com/web/tools/chrome-devtools/>.

=head2 Advantages Over L<WWW::Mechanize>

The Chrome browser provides advanced abilities useful for automating modern
web applications that are not (yet) possible with L<WWW::Mechanize> alone:

=over 4

=item *

Page content can be created or modified with JavaScript. You can also execute
custom JavaScript code on the page content.

=item *

Page content can be selected with CSS selectors.

=item *

Screenshots of the rendered page as an image or PDF file.

=back

=head2 Disadvantages

Installation of a Chrome compatible browser is required. There are some quirks
including sporadic, but harmless, error messages issued by the browser when
run with with DevTools.

=head2 A Brief Operational Overview

C<WWW::Mechanize::Chrome> (WMC) leverages developer tools built into Chrome and
Chrome-like browsers to control a browser instance programatically. You can use
WMC to automate tedious tasks, test web applications, and perform web scraping
operations.

Typically, WMC is used to launch both a I<host> instance of the browser and
provide a I<client> instance of the browser. The host instance of the browser is
visible to you on your desktop (unless the browser is running in "headless"
mode, in which case it will not open in a window). The client instance is the
Perl program you write with the WMC module to issue commands to control the host
instance. As you navigate and "click" on various nodes in the client browser,
you watch the host browser respond to these actions as if by magic.

This magic happens as a result of commands that are issued from your client to
the host using Chrome's DevTools Protocol which implements the http protocol to
send JSON data structures. The host also responds to the client with JSON to
describe the web pages it has loaded. WMC conveniently hides the complexity of
the lower level communications between the client and host browsers and wraps
them in a Perl object to provide the easy-to-use methods documented here.

=head1 OPTIONS

=head2 C<< WWW::Mechanize::Chrome->new( %options ) >>

  my $mech = WWW::Mechanize::Chrome->new();

=over 4

=item B<autodie>

  autodie => 0   # make HTTP errors non-fatal

By default, C<autodie> is set to true. If an HTTP error is encountered, the
program dies along with its associated browser instances. This frees you from
having to write error checks after every request. Setting this value to false
makes HTTP errors non-fatal, allowing the program to continue running if
there is an error.

=item B<host>

Set the host the browser listens on:

  host => '192.168.1.2'
  host => 'localhost'

Defaults to C<127.0.0.1>. The browser will listen for commands on the
specified host. The host address should be inaccessible from the internet.

=item B<port>

  port => 9223   # set port the launched browser will use for remote operation

Defaults to C<9222>. Commands to the browser will be issued through this port.

=item B<tab>

Specify the browser tab the Chrome browser will use:

  tab => 'current'
  tab => qr/PerlMonks/

By default, a web page is opened in a new browser tab. Setting C<tab> to
C<current> will use the current, active tab instead. Alternatively, to use an
existing inactive tab, you can pass a regular expression to match against the
existing tab's title. A false value implements the default behavior and a new
tab will be created.

=item B<autoclose>

  autoclose => 0   # keep tab open after program end

By default, C<autoclose> is set to true, closing the tab opened when running
your code. If C<autoclose> is set to a false value, the tab will remain open
even after the program has finished.

=item B<host>

Set the host the browser listens on:

  host => '192.168.1.2'
  host => 'localhost'

Defaults to C<127.0.0.1>. The browser will listen for commands on the
specified host. The host address should be inaccessible from the internet.
=item B<log>

  log => $object   # specify the object used for logging

Can be used to supply a L<Log::Log4perl> object that has been manually
constructed.

=item B<launch_exe>

Set the name and/or path to the browser's executable program:

  launch_exe => 'name-of-chrome-executabe'    # for non-standard executable names
  launch_exe => '/path/to/executable'         # for non-standard paths
  launch_exe => '/path/to/executable/chrome'  # full path

By default, C<WWW::Mechanize::Chrome> will search the appropriate paths for
Chrome's executable file based on the operating system. Use this option to set
the path to your executable if it is in a non-standard location or if the
executable has a non-standard name.

The default paths searched are those found in C<$ENV{PATH}>. For OS X, the user
and system C<Application> directories are also searched. The default values for
the executable file's name are C<chrome> on Windows, C<Google Chrome> on OS X,
and C<google-chrome> elsewhere.

If you want to use Chromium, you must specify that explicitly with something
like:

  launch_exe => 'chromium-browser', # if Chromium is named chromium-browser on your OS

Results my vary for your operating system. Use the full path to the browser's
executable if you are having issues. You can also set the name of the executable
file with the C<$ENV{CHROME_BIN}> environment variable.

=item B<start_url>

  start_url => 'http://perlmonks.org'  # Immediately navigate to a given URL

By default, the browser will open with a blank tab. Use the C<start_url> option
to open the browser to the specified URL. More typically, the C<< ->get >>
method is use to navigate to URLs.

=item B<launch_arg>

Pass additional switches and parameters to the browser's executable:

  launch_arg => [ "--some-new-parameter=foo", "--another-option" ]

Examples of other useful parameters include:

    '--start-maximized',
    '--window-size=1280x1696'
    '--ignore-certificate-errors'

    '--disable-web-security',
    '--allow-running-insecure-content',

    '--load-extension'
    '--no-sandbox'

=item B<profile>

  profile => '/path/to/profile/directory'  #  set the profile directory

By default, your current user profile directory is used. Use this setting
to change the profile directory for the browsing session.

=item B<incognito>

  incognito => 1   # open the browser in incognito mode

Defaults to false. Set to true to launch the browser in incognito mode.

=item B<data_directory>

  data_directory => '/path/to/data/directory'  #  set the data directory

By default, the current data directory is used. Use this setting to change the
base data directory for the browsing session.

  use File::Temp 'tempdir';
  # create a fresh Chrome every time
  my $mech = WWW::Mechanize::Chrome->new(
      data_directory => tempdir(CLEANUP => 1 ),
  );

=item B<startup_timeout>

  startup_timeout => 5  # set the startup timeout value

Defaults to 20, the maximum number of seconds to wait for the browser to launch.
Higher or lower values can be set based on the speed of the machine. The
process attempts to connect to the browser once each second over the duration
of this setting.

=item B<listen_host>

  listen_host => '192.1.168.7'  # set an IP address for listening

Specifies an IP address the launched browser process should listen on. This
option is useful for controlling the browser from another machine on your
network.

=item B<driver>

  driver => $driver_object  # specify the driver object

Use a L<Chrome::DevToolsProtocol> object that has been manually constructed.

=item B<report_js_errors>

  report_js_errors => 1  # turn javascript error reporting on

Defaults to false. If true, tests for Javascript errors and warns after each
request are run. This is useful for testing with C<use warnings qw(fatal)>.

=item B<mute_audio>

  mute_audio => 0  # turn sounds on

Defaults to true (sound off). A false value turns the sound on.

=item B<background_networking>

  background_networking => 1  # turn background networking on

Defaults to false (off). A true value enables background networking.

=item B<client_side_phishing_detection>

  client_side_phishing_detection => 1  # turn client side phishing detection on

Defaults to false (off). A true value enables client side phishing detection.

=item B<component_update>

  component_update => 1  # turn component updates on

Defaults to false (off). A true value enables component updates.

=item B<default_apps>

  default_apps => 1  # turn default apps on

Defaults to false (off). A true value enables default apps.

=item B<hang_monitor>

  hang_monitor => 1  # turn the hang monitor on

Defaults to false (off). A true value enables the hang monitor.

=item B<hide_scrollbars>

  hide_scrollbars => 1  # hide the scrollbars

Defaults to false (off). A true value will hide the scrollbars.

=item B<infobars>

  infobars => 1  # turn infobars on

Defaults to false (off). A true value will turn infobars on.

=item B<popup_blocking>

  popup_bloacking => 1  # block popups

Defaults to false (off). A true value will block popups.

=item B<prompt_on_repost>

  prompt_on_repost => 1  # allow prompts when reposting

Defaults to false (off). A true value will allow prompts when reposting.

=item B<save_password_bubble>

  save_password_bubble => 1  # allow the display of the save password bubble

Defaults to false (off). A true value allows the save password bubble to be
displayed.

=item B<sync>

  sync => 1   # turn syncing on

Defaults to false (off). A true value turns syncing on.

=item B<web_resources>

  web_resources => 1   # turn web resources on

Defaults to false (off). A true value turns web resources on.

=back

The C<< $ENV{WWW_MECHANIZE_CHROME_TRANSPORT} >> variable can be set to a
different transport class to override the default L<transport
class|Chrome::DevToolsProtcol::Transport>. This is primarily used for testing
but can also help eliminate introducing bugs from the underlying websocket
implementation(s).

=head1 METHODS

=cut

sub build_command_line {
    my( $class, $options )= @_;

    my @program_names = $class->default_executable_names( $options->{launch_exe} );

    my( $program, $error) = $class->find_executable(\@program_names);
    croak $error if ! $program;

    $options->{ launch_arg } ||= [];

    if( $options->{pipe}) {
        push @{ $options->{ launch_arg }}, "--remote-debugging-pipe";
    } else {

        $options->{port} ||= 9222
            if ! exists $options->{port};

        if ($options->{port}) {
            push @{ $options->{ launch_arg }}, "--remote-debugging-port=$options->{ port }";
        };

        if ($options->{listen_host}) {
            push @{ $options->{ launch_arg }}, "--remote-debugging-address==$options->{ listen_host }";
        };
    };

    if ($options->{incognito}) {
        push @{ $options->{ launch_arg }}, "--incognito";
    };

    if ($options->{data_directory}) {
        push @{ $options->{ launch_arg }}, "--user-data-dir=$options->{ data_directory }";
    };

    if ($options->{profile}) {
        push @{ $options->{ launch_arg }}, "--profile-directory=$options->{ profile }";
    };

    if( ! exists $options->{enable_automation} || $options->{enable_automation}) {
        push @{ $options->{ launch_arg }}, "--enable-automation";
    };

    if( ! exists $options->{enable_first_run} || ! $options->{enable_first_run}) {
        push @{ $options->{ launch_arg }}, "--no-first-run";
    };

    if( ! exists $options->{mute_audio} || $options->{mute_audio}) {
        push @{ $options->{ launch_arg }}, "--mute-audio";
    };

    if( ! exists $options->{no_zygote} || $options->{no_zygote}) {
        push @{ $options->{ launch_arg }}, "--no-zygote";
    };

    if( ! exists $options->{no_zygote} || $options->{no_sandbox}) {
        push @{ $options->{ launch_arg }}, "--no-sandbox";
    };

    if( $options->{hide_scrollbars}) {
        push @{ $options->{ launch_arg }}, "--hide-scrollbars";
    };

    if( exists $options->{disable_prompt_on_repost}) {
        carp "Option 'disable_prompt_on_repost' is deprecated, use prompt_on_repost instead";
        $options->{prompt_on_repost} = !$options->{disable_prompt_on_repost};
    };

    for my $option (qw(
        background_networking
        client_side_phishing_detection
        component_update
        hang_monitor
        prompt_on_repost
        sync
        web_resources
        default_apps
        infobars
        popup_blocking
        gpu
        save-password-bubble
    )) {
        (my $optname = $option) =~ s!_!-!g;
        if( ! exists $options->{$option}) {
            push @{ $options->{ launch_arg }}, "--disable-$optname";
        } elsif( ! (my $value = delete $options->{$option}))  {
            push @{ $options->{ launch_arg }}, "--disable-$optname";
        };
    };

    push @{ $options->{ launch_arg }}, "--headless"
        if $options->{ headless };

    push @{ $options->{ launch_arg }}, "$options->{start_url}"
        if exists $options->{start_url};

    my $quoted_program = ($^O =~ /mswin/i and $program =~ /[\s|<>&]/)
        ?  qq("$program")
        :  $program;

    my @cmd=( $program, @{ $options->{launch_arg}} );

    @cmd
};

=head2 C<< WWW::Mechanize::Chrome->find_executable >>

    my $chrome = WWW::Mechanize::Chrome->find_executable();

    my $chrome = WWW::Mechanize::Chrome->find_executable(
        'chromium.exe',
        '.\\my-chrome-66\\',
    );

    my( $chrome, $diagnosis ) = WWW::Mechanize::Chrome->find_executable(
        ['chromium-browser','google-chrome'],
        './my-chrome-66/',
    );
    die $diagnosis if ! $chrome;

Finds the first Chrome executable in the path (C<$ENV{PATH}>). For Windows, it
also looks in C<< $ENV{ProgramFiles} >>, C<< $ENV{ProgramFiles(x86)} >>
and C<< $ENV{"ProgramFilesW6432"} >>. For OSX it also looks in the user home
directory as given through C<< $ENV{HOME} >>.

This is used to find the default Chrome executable if none was given through
the C<launch_exe> option or if the executable is given and does not exist
and does not contain a directory separator.

=cut

sub default_executable_names( $class, @other ) {
    my @program_names
        = grep { defined($_) } (
        $ENV{CHROME_BIN},
        @other,
    );
    if( ! @program_names ) {
        push @program_names,
          $^O =~ /mswin/i ? 'chrome.exe'
        : $^O =~ /darwin/i ? 'Google Chrome'
        : ('google-chrome', 'chromium-browser', 'chromium')
    };
    @program_names
}

# Returns additional directories where the default executable can be found
# on this OS
sub additional_executable_search_directories( $class, $os_style=$^O ) {
    my @search;
    if( $os_style =~ /MSWin/i ) {
        push @search,
            map { "$_\\Google\\Chrome\\Application\\" }
            grep {defined}
            ($ENV{'ProgramFiles'},
             $ENV{'ProgramFiles(x86)'},
             $ENV{"ProgramFilesW6432"},
            );
    } elsif( $os_style =~ /darwin/i ) {
        my $path = '/Applications/Google Chrome.app/Contents/MacOS';
        push @search,
            $path,
            $ENV{"HOME"} . "/$path";
    }
    @search
}

sub find_executable( $class, $program=[$class->default_executable_names], @search) {
    my $looked_for = '';
    if( ! ref $program) {
        $program = [$program]
    };
    my $program_name = join ", ", map { qq('$_') } @$program;

    if( my($first_program) = grep { -x $_ } @$program) {
        # We've got a complete path, done!
        return $first_program
    };

    # Not immediately found, so we need to search
    my @without_path = grep { !m![/\\]! } @$program;

    if( @without_path) {
        push @search, File::Spec->path();
        push @search, $class->additional_executable_search_directories();
        $looked_for = ' in searchpath ' . join " ", @search;
    };

    my $found;

    for my $path (@search) {
        for my $p (@without_path) {
            my $this = File::Spec->catfile( $path, $p );
            if( -x $this ) {
                $found = $this;
                last;
            };
        };
    };

    if( wantarray ) {
        my $msg;
        if( ! $found) {
            $msg = "No executable like $program_name found$looked_for";
        };
        return $found, $msg
    } else {
        return $found
    };
}

sub _find_free_port( $class, $start ) {
    my $port = $start;
    while (1) {
        $port++, next unless IO::Socket::INET->new(
            Listen    => 5,
            Proto     => 'tcp',
            Reuse     => 1,
            LocalPort => $port
        );
        last;
    }
    $port;
}

sub _wait_for_socket_connection( $class, $host, $port, $timeout=20 ) {
    my $wait = time + $timeout;
    while ( time < $wait ) {
        my $t = time;
        my $socket = IO::Socket::INET->new(
            PeerHost => $host,
            PeerPort => $port,
            Proto    => 'tcp',
        );
        if( $socket ) {
            close $socket;
            sleep(1);
            last;
        };
        sleep(1) if time - $t < 1;
    }
    my $res = 1;
    if( time >= $wait ) {
        # No logger available yet
        #warn "Got timeout while waiting for Chrome at $host:$port";
        $res = 0;
    };
    $res
};

sub spawn_child_win32( $self, $method, @cmd ) {
    croak "Only socket communication is supported on $^O"
        if $method ne 'socket';
    system(1, @cmd)
}

sub spawn_child_posix( $self, $method, @cmd ) {
    require POSIX;
    POSIX->import("setsid");

    my (%child, %parent);
    if( $method eq 'pipe' ) {
        # Now, we want to have file handles with fileno=3 and fileno=4
        # to talk to Chrome v72+

        # Just open some filehandles to push the filenos above 4 for sure:
        open my $dummy_fh, '>', '/dev/null';
        open my $dummy_fh2, '>', '/dev/null';

        pipe $child{read}, $parent{write};
        pipe $parent{read}, $child{write};

        close $dummy_fh;
        close $dummy_fh2;
    };

    # daemonize
    defined(my $pid = fork())   || die "can't fork: $!";
    if( $pid ) {    # non-zero now means I am the parent
        if( $method eq 'pipe' ) {
            close $child{read};
            close $child{write};
        };
        return $pid, $parent{write}, $parent{read};
    };

    # We are the child, close about everything, then exec
    chdir("/")                  || die "can't chdir to /: $!";
    (setsid() != -1)            || die "Can't start a new session: $!";
    open(STDERR, ">&STDOUT")    || die "can't dup stdout: $!";
    open(STDIN,  "< /dev/null") || die "can't read /dev/null: $!";
    open(STDOUT, "> /dev/null") || die "can't write to /dev/null: $!";

    my ($from_chrome, $to_chrome);
    if( $method eq 'pipe' ) {
        # Those two handles belong to the parent
        close $parent{read};
        close $parent{write};

        # We want handles 0,1,2,3,4 to be inherited by Chrome
        $^F = 4;

        # Set up FD 3 and 4 for Chrome to read/write
        open($from_chrome, '<&', $child{read})|| die "can't open reader pipe: $!";
        open($to_chrome, '>&', $child{write})  || die "can't open writer pipe: $!";
    };
    exec @cmd;
    exit 1;
}

sub spawn_child( $self, $method, @cmd ) {
    my ($pid, $to_chrome, $from_chrome);
    if( $^O =~ /mswin/i ) {
        $pid = $self->spawn_child_win32($method, @cmd)
    } else {
        ($pid,$to_chrome,$from_chrome) = $self->spawn_child_posix($method, @cmd)
    };
    $self->log('debug', "Spawned child as $pid");

    return ($pid,$to_chrome,$from_chrome)
}

sub _build_log( $self ) {
    require Log::Log4perl;
    Log::Log4perl->get_logger(__PACKAGE__);
}

# The generation of node ids
sub _generation( $self, $val=undef ) {
    @_ == 2 and $self->{_generation} = $_[1];
    $self->{_generation}
};

sub new_generation( $self ) {
    $self->_generation( ($self->_generation() ||0) +1 );
}

sub log( $self, $level, $message, @args ) {
    my $logger = $self->{log};
    if( !@args ) {
        $logger->$level( $message )
    } else {
        my $enabled = "is_$level";
        $logger->$level( join " ", $message, Dumper @args )
            if( $logger->$enabled );
    };
}

sub new($class, %options) {

    if (! exists $options{ autodie }) {
        $options{ autodie } = 1
    };

    if( ! exists $options{ frames }) {
        $options{ frames }= 1;
    };

    if( ! exists $options{ download_directory }) {
        $options{ download_directory }= '';
    };

    $options{ js_events } ||= [];
    if( ! exists $options{ transport }) {
        $options{ transport } ||= $ENV{ WWW_MECHANIZE_CHROME_TRANSPORT };
    };

    $options{start_url} = 'about:blank'
        unless exists $options{start_url};

    my $host = $options{ host } || '127.0.0.1';

    $options{ reuse } ||= defined $options{ tab };
    $options{ extra_headers } ||= {};

    if( $options{ tab } and $options{ tab } eq 'current' ) {
        $options{ tab } = 0; # use tab at index 0
    };

    my $method = 'socket';
    #if( ! $options{ port } and ! $options{ pid } and ! $options{ reuse }) {
    if( $options{ pipe }) {
        #$options{ pipe } = 1;
        $method = 'pipe';
    };

    my $self= bless \%options => $class;
    $self->{log} ||= $self->_build_log;

    my( $to_chrome, $from_chrome );
    unless ($options{pid} or $options{reuse}) {
        unless ( defined $options{ port } ) {
            # Find free port for Chrome to listen on
            $options{ port } = $class->_find_free_port( 9222 );
        };

        my @cmd= $class->build_command_line( \%options );
        $self->log('debug', "Spawning", \@cmd);
        (my( $pid ), $to_chrome, $from_chrome ) = $self->spawn_child( $method, @cmd );
        $options{ writer_fh } = $to_chrome;
        $options{ reader_fh } = $from_chrome;
        $self->{pid} = $pid;
        $self->{ kill_pid } = 1;

        if( ! $options{ pipe } ) {
            # Just to give Chrome time to start up, make sure it accepts connections
            my $ok = $self->_wait_for_socket_connection( $host, $self->{port}, $self->{startup_timeout} || 20);
            if( ! $ok) {
                die "Timeout while connecting to $host:$self->{port}. Do you maybe have a non-debug instance of Chrome already running?";
            };
        };
    } else {

        # Assume some defaults for the already running Chrome executable
        $options{ port } //= 9222;
    };

    my @connection;
    if( $options{ pipe }) {
        @connection = (
            writer_fh => $options{ writer_fh },
            reader_fh => $options{ reader_fh },
        );
    } else {
        @connection = (
            port => $options{ port },
            host => $host,
        );
    };

    # Connect to it via TCP or local pipe
    $options{ driver } ||= Chrome::DevToolsProtocol->new(
        @connection,
        auto_close => 0,
        error_handler => sub {
            #warn ref$_[0];
            #warn "<<@CARP_NOT>>";
            #warn ((caller($_))[0,1,2])
            #    for 1..4;
            local @CARP_NOT = (@CARP_NOT, ref $_[0],'Try::Tiny');
            # Reraise the error
            croak $_[1]
        },
        transport => $options{ transport },
        log => $options{ log },
    );

    # Synchronously connect here, just for easy API compatibility
    $self->_connect(%options);

    $self
};

sub _setup_driver_future( $self, %options ) {
    $self->driver->connect(
        new_tab => !$options{ reuse },
        tab     => $options{ tab },
        writer_fh => $options{ writer_fh },
        reader_fh => $options{ reader_fh },
    )->catch( sub(@args) {
        my $err = $args[0];
        if( ref $args[1] eq 'HASH') {
            $err .= $args[1]->{Reason};
        };
        Future->fail( $err );
    })
}

sub _build_debuggerTransport( $self ) {
    my $targetId;
    $self->driver->send_message('Target.createBrowserContext')->then(sub {
        $self->driver->send_message('Target.createTarget',
            url => 'about:blank',
            browserContextId => $_[0]->{browserContextId},
        );
    })->then(sub {
        $targetId = $_[0]->{targetId};
        $self->driver->send_message('Target.attachToTarget',
            targetId => $_[0]->{targetId},
        );
    })->then(sub {
        Future->done( $targetId );
    });
}

# This (tries to) connects to the devtools in the browser
sub _connect( $self, %options ) {
    my $err;
    $self->_setup_driver_future( %options )
    ->catch( sub(@args) {
        $err = $args[0];
        Future->fail( @args );
    })->get;

    # if Chrome started, but so slow or unresponsive that we cannot connect
    # to it, kill it manually to avoid waiting for it indefinitely
    if ( $err ) {
        if( $self->{ kill_pid } and my $pid = delete $self->{ pid }) {
            local $SIG{CHLD} = 'IGNORE';
            kill 'SIGKILL' => $pid;
            waitpid $pid, 0;
        };
        croak $err;
    }

    # Create new world if needed
    # connect to current world/new world

    my $s = $self;
    weaken $s;
    my $collect_JS_problems = sub( $msg ) {
        $s->_handleConsoleAPICall( $msg->{params} )
    };
    $self->{consoleAPIListener} =
        $self->add_listener( 'Runtime.consoleAPICalled', $collect_JS_problems );
    $self->{exceptionThrownListener} =
        $self->add_listener( 'Runtime.exceptionThrown', $collect_JS_problems );
    $self->{nodeGenerationChange} =
        $self->add_listener( 'DOM.attributeModified', sub { $s->new_generation() } );
    $self->new_generation;

    # We need to set up a new browser target if we connect via pipe
    my $targetId;
    #if( $options{ pipe }) {
        $targetId = $self->_build_debuggerTransport()->get;
        require Chrome::DevToolsProtocol::Target;
        $self->{target} = Chrome::DevToolsProtocol::Target->new(
            transport => $self->{driver},
            targetId  => $targetId,
        );
        $self->{target}->connect()->get;
        $self->{driver} = $self->{target};
        # Now, replace driver with the driver sending to the target
        #$self->driver->send_message('Target.sendMessageToTarget',
            #targetId => $targetId, message => '{"id":0,"method":"Page.enable"}');
        # $self->transport->send_message()
        # ->transport -> { sendMessageToTarget( message ) }
        # ->       target        ->
        # ->       driver       ->
    #};

    my @setup = (
        $self->driver->send_message('DOM.enable'),
        $self->driver->send_message('Page.enable'),    # capture DOMLoaded
        $self->driver->send_message('Network.enable'), # capture network
        $self->driver->send_message('Runtime.enable'), # capture console messages
        #$self->driver->send_message('Debugger.enable'), # capture "script compiled" messages
        $self->set_download_directory_future($self->{download_directory}),

        keys %{$options{ extra_headers }} ? $self->_set_extra_headers_future( %{$options{ extra_headers }} ) : (),
    );

    if( my $agent = delete $options{ user_agent }) {
        push @setup, $self->agent_future( $agent );
    };

    Future->wait_all(
        @setup,
    )->get;

    # ->get() doesn't have ->get_future() yet
    if( ! (exists $options{ tab } )) {
        $self->get($options{ start_url }); # Reset to clean state, also initialize our frame id
    };
}

sub _handleConsoleAPICall( $self, $msg ) {
    if( $self->{report_js_errors}) {
        my $desc = $msg->{exceptionDetails}->{exception}->{description};
        my $loc  = $msg->{exceptionDetails}->{stackTrace}->{callFrames}->[0]->{url};
        my $line = $msg->{exceptionDetails}->{stackTrace}->{callFrames}->[0]->{lineNumber};
        my $err = "$desc at $loc line $line";
        $self->log('error', $err);
    };
    push @{$self->{js_events}}, $msg;
}

sub frameId( $self ) {
    $self->{frameId}
}

sub requestId( $self ) {
    $self->{requestId}
}

=head2 C<< $mech->chrome_version >>

  print $mech->chrome_version;

Returns the version of the Chrome executable being used. This information
needs launching the browser and asking for the version via the network.

=cut

sub chrome_version_from_stdout( $self ) {
    # We can try to get at the version through the --version command line:
    my @cmd = $self->build_command_line({ launch_arg => ['--version'], headless => 0, enable_automation => 0, port => undef });
    #$self->log('trace', "Retrieving version via [@cmd]" );
    if ($^O =~ /darwin/) {
      s/ /\\ /g for @cmd;
    }
    my $v = readpipe(join " ", @cmd);

    # Chromium 58.0.3029.96 Built on Ubuntu , running on Ubuntu 14.04
    # Chromium 76.0.4809.100 built on Debian 10.0, running on Debian 10.0
    $v =~ /^(\S+)\s+([\d\.]+)\s/
        or return; # we didn't find anything
    return "$1/$2"
}

sub chrome_version( $self ) {
    if( $^O !~ /mswin/i ) {
        my $version = $self->chrome_version_from_stdout();
        if( $version ) {
            return $version;
        };
    };

    $self->chrome_version_info()->{Browser}
}

=head2 C<< $mech->chrome_version_info >>

  print $mech->chrome_version_info->{Browser};

Returns the version information of the Chrome executable and various other
APIs of Chrome that the object is connected to.

=cut

sub chrome_version_info( $self ) {
    $self->{chrome_version} ||= do {
        $self->driver->version_info->get;
    };
}

=head2 C<< $mech->driver >>

    my $driver = $mech->driver

Access the L<Chrome::DevToolsProtocol> instance connecting to Chrome.

=cut

sub driver {
    $_[0]->{driver}
};

sub target {
    $_[0]->{target}
};

=head2 C<< $mech->tab >>

    my $tab = $mech->tab

Access the tab hash of the L<Chrome::DevToolsProtocol> instance connecting
to Chrome. This represents the tab we control.

=cut

sub tab( $self ) {
    $self->driver->tab
}

sub autodie {
    my( $self, $val )= @_;
    $self->{autodie} = $val
        if @_ == 2;
    $_[0]->{autodie}
}

=head2 C<< $mech->allow( %options ) >>

  $mech->allow( javascript => 1 );

Allow or disallow execution of Javascript

=cut

sub allow {
    my($self,%options)= @_;

    my @await;
    if( exists $options{ javascript } ) {
        my $disabled = !$options{ javascript } ? JSON::true : JSON::false;
        push @await,
            $self->driver->send_message('Emulation.setScriptExecutionDisabled', value => $disabled );
    };

    Future->wait_all( @await )->get;
}

=head2 C<< $mech->emulateNetworkConditions( %options ) >>

  # Go offline
  $mech->emulateNetworkConditions(
      offline => JSON::true,
      latency => 10, # ms ping
      downloadThroughput => 0, # bytes/s
      uploadThroughput => 0, # bytes/s
      connectionType => 'offline', # cellular2g, cellular3g, cellular4g, bluetooth, ethernet, wifi, wimax, other.
  );

=cut

sub emulateNetworkConditions_future( $self, %options ) {
    $options{ offline } //= JSON::false,
    $options{ latency } //= -1,
    $options{ downloadThroughput } //= -1,
    $options{ uploadThroughput } //= -1,
    $self->driver->send_message('Network.emulateNetworkConditions', %options)
}

sub emulateNetworkConditions( $self, %options ) {
    $self->emulateNetworkConditions_future( %options )->get
}

=head2 C<< $mech->setRequestInterception( @patterns ) >>

  $mech->setRequestInterception(
      { urlPattern => '*', resourceType => 'Document', interceptionStage => 'Request'},
      { urlPattern => '*', resourceType => 'Media', interceptionStage => 'Response'},
  );

Sets the list of request patterns and resource types for which the interception
callback will be invoked.

=cut

sub setRequestInterception_future( $self, @patterns ) {
    $self->driver->send_message('Network.setRequestInterception', patterns => @patterns)
}

sub setRequestInterception( $self, @patterns ) {
    $self->setRequestInterception_future( @patterns )->get
}

=head2 C<< $mech->add_listener >>

  my $url_loaded = $mech->add_listener('Network.responseReceived', sub {
      my( $info ) = @_;
      warn "Loaded URL "
           . $info->{params}->{response}->{url}
           . ": "
           . $info->{params}->{response}->{status};
      warn "Resource timing: " . Dumper $info->{params}->{response}->{timing};
  });

Returns a listener object. If that object is discarded, the listener callback
will be removed.

Calling this method in void context croaks.

To see the browser console live from your Perl script, use the following:

  my $console = $mech->add_listener('Runtime.consoleAPICalled', sub {
    warn join ", ",
        map { $_->{value} // $_->{description} }
        @{ $_[0]->{params}->{args} };
  });

If you want to explicitly remove the listener, either set it to C<undef>:

  undef $console;

Alternatively, call

  $console->unregister;

or call

  $mech->remove_listener( $console );

=cut

sub add_listener( $self, $event, $callback ) {
    if( ! defined wantarray ) {
        croak "->add_listener called in void context."
            . "Please store the result somewhere";
    };
    return $self->driver->add_listener( $event, $callback )
}

sub remove_listener( $self, $listener ) {
    $listener->unregister
}

=head2 C<< $mech->on_request_intercepted( $cb ) >>

  $mech->on_request_intercepted( sub {
      my( $mech, $info ) = @_;
      warn $info->{request}->{url};
      $mech->continueInterceptedRequest_future(
          interceptionId => $info->{interceptionId}
      )
  });

A callback for intercepted requests that match the patterns set up
via C<setRequestInterception>.

If you return a future from this callback, it will not be discarded but kept in
a safe place.

=cut

sub on_request_intercepted( $self, $cb ) {
    if( $cb ) {
        my $s = $self;
        weaken $s;
        $self->{ on_request_intercept_listener } =
        $self->add_listener('Network.requestIntercepted', sub( $ev ) {
            if( $s->{ on_request_intercepted }) {
                $s->log('debug', sprintf 'Request intercepted %s: %s',
                                    $ev->{params}->{interceptionId},
                                    $ev->{params}->{request}->{url});
                $s->{ on_request_intercepted }->( $s, $ev->{params} );
            };
        });
    } else {
        delete $self->{ on_request_intercept_listener };
    };
    $self->{ on_request_intercepted } = $cb;
}

=head2 C<< $mech->searchInResponseBody( $id, %options ) >>

  my $request_id = ...;
  my @matches = $mech->searchInResponseBody(
      requestId     => $request_id,
      query         => 'rumpelstiltskin',
      caseSensitive => JSON::true,
      isRegex       => JSON::false,
  );
  for( @matches ) {
      print $_->{lineNumber}, ":", $_->{lineContent}, "\n";
  };

Returns the matches (if any) for a string or regular expression within
a response.

=cut

sub searchInResponseBody_future( $self, %options ) {
    $self->driver->send_message('Network.searchInResponseBody', %options)
    ->then(sub( $res ) {
        return Future->done( @{ $res->{result}} )
    })
}

sub searchInResponseBody( $self, @patterns ) {
    $self->searchInResponseBody_future( @patterns )->get
}

=head2 C<< $mech->on_dialog( $cb ) >>

  $mech->on_dialog( sub {
      my( $mech, $dialog ) = @_;
      warn $dialog->{message};
      $mech->handle_dialog( 1 ); # click "OK" / "yes" instead of "cancel"
  });

A callback for Javascript dialogs (C<< alert() >>, C<< prompt() >>, ... )

=cut

sub on_dialog( $self, $cb ) {
    if( $cb ) {
        my $s = $self;
        weaken $s;
        $self->{ on_dialog_listener } =
        $self->add_listener('Page.javascriptDialogOpening', sub( $ev ) {
            if( $s->{ on_dialog }) {
                $s->log('debug', sprintf 'Javascript %s: %s', $ev->{params}->{type}, $ev->{params}->{message});
                $s->{ on_dialog }->( $s, $ev->{params} );
            };
        });
    } else {
        delete $self->{ on_dialog_listener };
    };
    $self->{ on_dialog } = $cb;
}

=head2 C<< $mech->handle_dialog( $accept, $prompt = undef ) >>

  $mech->on_dialog( sub {
      my( $mech, $dialog ) = @_;
      warn "[Javascript $dialog->{type}]: $dialog->{message}";
      $mech->handle_dialog( 1 ); # click "OK" / "yes" instead of "cancel"
  });

Closes the current Javascript dialog. Depending on

=cut

sub handle_dialog( $self, $accept, $prompt = undef ) {
    my $v = $accept ? JSON::true : JSON::false;
    $self->log('debug', sprintf 'Dismissing Javascript dialog with %d', $accept);
    my $f;
    $f = $self->driver->send_message(
        'Page.handleJavaScriptDialog',
        accept => $v,
        promptText => (defined $prompt ? $prompt : 'generic message'),
    )->then( sub {
        # We deliberately ignore the result here
        # to avoid deadlock of Futures
        undef $f;
    });
};

=head2 C<< $mech->js_console_entries() >>

  print $_->{type}, " ", $_->{message}, "\n"
      for $mech->js_console_entries();

An interface to the Javascript Error Console

Returns the list of entries in the JEC

=cut

sub js_console_entries( $self ) {
    @{$self->{js_events}}
}

=head2 C<< $mech->js_errors() >>

  print "JS error: ", $_->{message}, "\n"
      for $mech->js_errors();

Returns the list of errors in the JEC

=cut

sub js_errors {
    my ($self) = @_;
    grep { ($_->{type} || '') ne 'log' } $self->js_console_entries
}

=head2 C<< $mech->clear_js_errors() >>

    $mech->clear_js_errors();

Clears all Javascript messages from the console

=cut

sub clear_js_errors {
    my ($self) = @_;
    @{$self->{js_events}} = ();
    $self->driver->send_message('Runtime.discardConsoleEntries')->get;
};

=head2 C<< $mech->eval_in_page( $str, %options ) >>

=head2 C<< $mech->eval( $str, %options ) >>

  my ($value, $type) = $mech->eval( '2+2' );

Evaluates the given Javascript fragment in the
context of the web page.
Returns a pair of value and Javascript type.

This allows access to variables and functions declared
"globally" on the web page.

=over 4

=item returnByValue

If you want to create an object in Chrome and only want to keep a handle to that
remote object, use C<JSON::false> for the C<returnByValue> option:

    my ($dummyObj,$type) = $mech->eval(
        'new Object',
        returnByValue => JSON::false
    );

This is also helpful if the object in Chrome cannot be serialized as JSON.
For example, C<window> is such an object. The return value is a hash, whose
C<objectId> is the most interesting part.

=back

This method is special to WWW::Mechanize::Chrome.

=cut

sub eval_in_page($self,$str, %options) {
    # Report errors from scope of caller
    # This feels weirdly backwards here, but oh well:
    local @Chrome::DevToolsProtocol::CARP_NOT
        = (@Chrome::DevToolsProtocol::CARP_NOT, (ref $self)); # we trust this
    local @CARP_NOT
        = (@CARP_NOT, 'Chrome::DevToolsProtocol', (ref $self)); # we trust this
    my $result = $self->driver->evaluate("$str", %options)->get;

    if( $result->{error} ) {
        $self->signal_condition(
            join "\n", grep { defined $_ }
                           $result->{error}->{message},
                           $result->{error}->{data},
                           $result->{error}->{code}
        );
    } elsif( $result->{exceptionDetails} ) {
        $self->signal_condition(
            join "\n", grep { defined $_ }
                           $result->{exceptionDetails}->{text},
                           $result->{exceptionDetails}->{exception}->{description},
        );
    }

    if( exists $result->{result}->{value}) {
        return $result->{result}->{value}, $result->{result}->{type};
    } else {
        return $result->{result}, $result->{result}->{type};
    }
};

{
    no warnings 'once';
    *eval = \&eval_in_page;
}

=head2 C<< $mech->eval_in_chrome $code, @args >>

  $mech->eval_in_chrome(<<'JS', "Foobar/1.0");
      this.settings.userAgent= arguments[0]
  JS

Evaluates Javascript code in the context of Chrome.

This allows you to modify properties of Chrome.

This is currently not implemented.

=cut

sub eval_in_chrome {
    my ($self, $code, @args) = @_;
    croak "Can't call eval_in_chrome";
};

=head2 C<< $mech->callFunctionOn( $function, @arguments ) >>

  my ($value, $type) = $mech->callFunctionOn( 'function(greeting) { alert(greeting)}', 'Hello World' );

Runs the given function with the specified arguments.

This method is special to WWW::Mechanize::Chrome.

=cut

sub callFunctionOn_future( $self, $str, %options ) {
    # Report errors from scope of caller
    # This feels weirdly backwards here, but oh well:
    local @Chrome::DevToolsProtocol::CARP_NOT
        = (@Chrome::DevToolsProtocol::CARP_NOT, (ref $self)); # we trust this
    local @CARP_NOT
        = (@CARP_NOT, 'Chrome::DevToolsProtocol', (ref $self)); # we trust this
    $self->driver->callFunctionOn($str, %options)
    ->then( sub( $result ) {

        if( $result->{error} ) {
            $self->signal_condition(
                join "\n", grep { defined $_ }
                               $result->{error}->{message},
                               $result->{error}->{data},
                               $result->{error}->{code}
            );
        } elsif( $result->{exceptionDetails} ) {
            $self->signal_condition(
                join "\n", grep { defined $_ }
                               $result->{exceptionDetails}->{text},
                               $result->{exceptionDetails}->{exception}->{description},
            );
        }
        if( exists $result->{result}->{value}) {
            return Future->done( $result->{result}->{value}, $result->{result}->{type} );
        } else {
            return Future->done( $result->{result}, $result->{result}->{type} );
        }
    })
};

sub callFunctionOn {
    my ($self,$str, %options) = @_;
    # Report errors from scope of caller
    # This feels weirdly backwards here, but oh well:
    local @Chrome::DevToolsProtocol::CARP_NOT
        = (@Chrome::DevToolsProtocol::CARP_NOT, (ref $self)); # we trust this
    local @CARP_NOT
        = (@CARP_NOT, 'Chrome::DevToolsProtocol', (ref $self)); # we trust this
    $self->callFunctionOn_future($str, %options)->get;
};

{
    no warnings 'once';
    *eval = \&eval_in_page;
}

sub agent_future( $self, $ua ) {
    $self->driver->send_message('Network.setUserAgentOverride', userAgent => $ua )
}

sub agent( $self, $ua ) {
    if( $ua ) {
        $self->agent_future( $ua )->get;
    };

    $self->chrome_version_info->{"User-Agent"}
}

=head2 C<< ->autoclose_tab >>

Set the C<autoclose> option

=cut

sub autoclose_tab( $self, $autoclose ) {
    $self->{autoclose} = $autoclose
}

sub DESTROY {
    my $pid= delete $_[0]->{pid};

    if( $_[0]->{autoclose} and $_[0]->tab and my $tab_id = $_[0]->tab->{id} ) {
        $_[0]->driver->close_tab({ id => $tab_id })->get();
    };

    #if( $pid and $_[0]->{cached_version} > 65) {
    #    # Try a graceful shutdown
    #    $_[0]->driver->send_message('Browser.close' )->get
    #};

    local $@;
    eval {
        # Shut down our websocket connection
        if( $_[0]->{ driver }) {
            $_[0]->{ driver }->close
        };
    };
    delete $_[0]->{ driver };

    if( $pid ) {
        local $SIG{CHLD} = 'IGNORE';
        kill 'SIGKILL' => $pid;
        waitpid $pid, 0;
    };
    %{ $_[0] }= (); # clean out all other held references
}

=head2 C<< $mech->highlight_node( @nodes ) >>

    my @links = $mech->selector('a');
    $mech->highlight_node(@links);
    print $mech->content_as_png();

Convenience method that marks all nodes in the arguments
with a red frame.

This is convenient if you need visual verification that you've
got the right nodes.

=cut

sub highlight_node {
    my ($self,@nodes) = @_;
    for (@nodes) {
        #  Overlay.highlightNode
        my $style= $self->eval_in_page(<<JS, $_);
        (function(el) {
            if( 'none' == el.style.display ) {
                el.style.display= 'block';
            };
            el.style.background= 'red';
            el.style.border= 'solid black 1px';
        })(arguments[0]);
JS
    };
};

=head1 NAVIGATION METHODS

=head2 C<< $mech->get( $url, %options ) >>

  my $response = $mech->get( $url );

Retrieves the URL C<URL>.

It returns a L<HTTP::Response> object for interface compatibility
with L<WWW::Mechanize>.

Note that the returned L<HTTP::Response> object gets the response body
filled in lazily, so you might have to wait a moment to get the response
body from the result. This is a premature optimization and later releases of
WWW::Mechanize::Chrome are planned to fetch the response body immediately when
accessing the response body.

Note that Chrome does not support download of files through the API.

=head3 Options

=over 4

=item *

C<intrapage> - Override the detection of whether to wait for a HTTP response
or not. Setting this will never wait for an HTTP response.

=back

=cut

sub update_response($self, $response) {
    $self->log('trace', 'Updated response object');
    $self->{response} = $response
}

=head2 C<< $mech->_collectEvents >>

  my $events = $mech->_collectEvents(
      sub { $_[0]->{method} eq 'Page.loadEventFired' }
  );
  my( $e,$r) = Future->wait_all( $events, $self->driver->send_message(...));

Internal method to create a Future that waits for an event that is sent by Chrome.

The subroutine is the predicate to check to see if the current event
is the event we have been waiting for.

The result is a Future that will return all captured events.

=cut

sub _collectEvents( $self, @info ) {
    # Read the stuff that the driver sends to us:
    my $predicate = pop @info;
    ref $predicate eq 'CODE'
        or die "Need a predicate as the last parameter, not '$predicate'!";

    my @events = ();
    my $done = $self->driver->future;
    my $s = $self;
    weaken $s;
    $self->driver->on_message( sub( $message ) {
        push @events, $message;
        if( $predicate->( $events[-1] )) {
            my $frameId = $events[-1]->{params}->{frameId};
            $s->log( 'debug', "Received final message, unwinding", sprintf "(%s)", $frameId || '-');
            $s->log( 'trace', "Received final message, unwinding", $events[-1] );
            $s->driver->on_message( undef );
            $done->done( @info, @events );
        };
    });
    $done
}

sub _fetchFrameId( $self, $ev ) {
    if( $ev->{method} eq 'Page.frameStartedLoading'
        || $ev->{method} eq 'Page.frameScheduledNavigation'
        || $ev->{method} eq 'Network.requestWillBeSent'
    ) {
        my $frameId = $ev->{params}->{frameId};
        $self->log('debug', sprintf "Found frame id as %s", $frameId);
        return  ($frameId);
    }
};

sub _fetchRequestId( $self, $ev ) {
    if( $ev->{method} eq 'Page.frameStartedLoading'
        || $ev->{method} eq 'Page.frameScheduledNavigation'
        || $ev->{method} eq 'Network.requestWillBeSent'
    ) {
        my $requestId = $ev->{params}->{requestId};
        if( $requestId ) {
            $self->log('debug', sprintf "Found request id as %s", $requestId);
            return  ($requestId);
        } else {
            return
        };
    }
};

sub _waitForNavigationEnd( $self, %options ) {
    # Capture all events as we seem to have initiated some network transfers
    # If we see a Page.frameScheduledNavigation then Chrome started navigating
    # to a new page in response to our click and we should wait until we
    # received all the navigation events.

    my $frameId = $options{ frameId } || $self->frameId;
    my $requestId = $options{ requestId } || $self->requestId;
    my $msg = "Capturing events until 'Page.frameStoppedLoading' for frame $frameId";
    $msg .= " or 'Network.loadingFailed' or 'Network.loadingFinished' for request '$requestId'"
        if $requestId;

    $self->log('debug', $msg);
    my $events_f = $self->_collectEvents( sub( $ev ) {
        # Let's assume that the first frame id we see is "our" frame
        $frameId ||= $self->_fetchFrameId($ev);
        $requestId ||= $self->_fetchRequestId($ev);
        my $stopped = (    $ev->{method} eq 'Page.frameStoppedLoading'
                       && $ev->{params}->{frameId} eq $frameId);
        # This means basically no navigation events will follow:
        my $internal_navigation = (   $ev->{method} eq 'Page.navigatedWithinDocument'
                       && $requestId
                       && (! exists $ev->{params}->{requestId} or $ev->{params}->{requestId} eq $requestId));
        # This is far too early, but some requests only send this?!
        # Maybe this can be salvaged by setting a timeout when we see this?!
        my $domcontent = (  1 # $options{ just_request }
                       && $ev->{method} eq 'Page.domContentEventFired', # this should be the only one we need (!)
                       # but we never learn which page (!). So this does not play well with iframes :(
        );

        my $failed  = (   $ev->{method} eq 'Network.loadingFailed'
                       && $requestId
                       && $ev->{params}->{requestId} eq $requestId);
        my $download= (   $ev->{method} eq 'Network.responseReceived'
                       && $requestId
                       && $ev->{params}->{requestId} eq $requestId
                       && exists $ev->{params}->{response}->{headers}->{"Content-Disposition"}
                       && $ev->{params}->{response}->{headers}->{"Content-Disposition"} =~ m!^attachment\b!
                       );
        return $stopped || $internal_navigation || $failed || $download # || $domcontent;
    });

    $events_f;
}

sub _mightNavigate( $self, $get_navigation_future, %options ) {
    undef $self->{frameId};
    undef $self->{requestId};
    my $frameId = $options{ frameId };
    my $requestId = $options{ requestId };

    my $scheduled = $self->driver->one_shot(
        'Page.frameScheduledNavigation',
        'Page.frameStartedLoading',
        'Network.requestWillBeSent',      # trial
        #'Page.frameResized',              # download
        'Inspector.detached',             # Browser (window) was closed by user
        'Page.navigatedWithinDocument',
    );
    my $navigated;
    my $does_navigation;
    my $target_url = $options{ url };

    {
    my $s = $self;
    weaken $s;
    $does_navigation = $scheduled
        ->then(sub( $ev ) {
            my $res;
            if(     $ev->{method} eq 'Page.frameResized'
                and 0+keys %{ $ev->{params} } == 0 ) {
                # This is dead code that is never reached (see above)
                # Chrome v64 doesn't indicate at all to the API that a
                # download started :-(
                # Also, we won't know that it finished, or what name the
                # file got
                # At least unless we try to parse that from the response body :(
                $s->log('trace', "Download started, returning synthesized event");
                $navigated++;
                $s->{ frameId } = $ev->{params}->{frameId};
                $res = Future->done(
                    # Since Chrome v64,
                    { method => 'MechanizeChrome.download', params => {
                        frameId => $ev->{params}->{frameId},
                        loaderId => $ev->{params}->{loaderId},
                        response => {
                            status => 200,
                            statusText => 'faked response',
                            headers => {
                                'Content-Disposition' => 'attachment; filename=unknown',
                            }
                    }}
                })

            } elsif( $ev->{method} eq 'Inspector.detached' ) {
                $s->log('error', "Inspector was detached");
                $res = Future->fail("Inspector was detached");

            } elsif( $ev->{method} eq 'Page.navigatedWithinDocument' ) {
                $s->log('trace', "Intra-page navigation started, logging ($ev->{method})");
                $frameId ||= $s->_fetchFrameId( $ev );
                $res = Future->done(
                    # Since Chrome v64,
                    { method => 'Page.intra-page-navigation', params => {
                        frameId => $ev->{params}->{frameId},
                        loaderId => $ev->{params}->{loaderId},
                        response => {
                            status => 200,
                            statusText => 'faked response',
                    }}
                })

            } else {
                  $s->log('trace', "Navigation started, logging ($ev->{method})");
                  $navigated++;

                  $frameId ||= $s->_fetchFrameId( $ev );
                  $requestId ||= $s->_fetchRequestId( $ev );
                  $s->{ frameId } = $frameId;
                  $s->{ requestId } = $requestId;

                  $res = $s->_waitForNavigationEnd( %options )
            };
            return $res
        });
    };

    # Kick off the navigation ourselves
    my $nav;
    $get_navigation_future->()
    ->then( sub {
        $nav = $_[0];

        # We have a race condition to find out whether Chrome navigates or not
        # so we wait a bit to see if it will navigate in response to our click
        $self->sleep_future(0.1); # X XX baad fix
    })->then( sub {
        my $f;
        my @events;
        if( !$options{ intrapage } and $navigated ) {
            $f = $does_navigation->then( sub {
                @events = @_;
                # Handle all the events, by turning them into a ->response again
                my $res = $self->httpMessageFromEvents( $self->frameId, \@events, $target_url );
                $self->update_response( $res );
                $scheduled->cancel;
                undef $scheduled;

                # Store our frame id so we know what events to listen for in the future!
                $self->{frameId} ||= $nav->{frameId};

                Future->done( \@events )
            })
        } else {
            $self->log('trace', "No navigation occurred, not collecting events");
            $does_navigation->cancel;
            $f = Future->done(\@events);
            $scheduled->cancel;
            undef $scheduled;
        };

        return $f
    })
}

sub get_future($self, $url, %options ) {

    # $frameInfo might come _after_ we have already seen messages for it?!
    # So we need to capture all events even before we send our command to the
    # browser, as we might receive messages before we receive the answer to
    # our command:
    my $s = $self;
    weaken $s;
    my $events = $self->_mightNavigate( sub {
        $s->log('debug', "Navigating to [$url]");
        $s->driver->send_message(
            'Page.navigate',
            url => "$url"
        )
        }, url => "$url", %options, navigates => 1 )
    ->then( sub {
        Future->done( $self->response )
    })
};

sub get($self, $url, %options ) {

    $self->get_future($url, %options)->get;
};

=head2 C<< $mech->get_local( $filename , %options ) >>

  $mech->get_local('test.html');

Shorthand method to construct the appropriate
C<< file:// >> URI and load it into Chrome. Relative
paths will be interpreted as relative to C<$0>
or the C<basedir> option.

This method accepts the same options as C<< ->get() >>.

This method is special to WWW::Mechanize::Chrome but could
also exist in WWW::Mechanize through a plugin.

B<Warning>: Chrome does not handle local files well. Especially
subframes do not get loaded properly.

=cut

sub get_local {
    my ($self, $htmlfile, %options) = @_;
    my $basedir;
    if( exists $options{ basedir }) {
        $basedir = $options{ basedir };
    } else {
        require Cwd;
        require File::Spec;
        $basedir = dirname($0);
    };

    my $fn = File::Spec->rel2abs( $htmlfile, $basedir );
    $fn =~ s!\\!/!g; # fakey "make file:// URL"
    my $url;
    if( $^O =~ /mswin/i ) {
        $url= "file:///$fn";
    } else {
        $url= "file://$fn";
    };
    my $res = $self->get($url, %options);
    ## Chrome is not helpful with its error messages for local URLs
    #if( 0+$res->headers->header_field_names and ([$res->headers->header_field_names]->[0] ne 'x-www-mechanize-Chrome-fake-success' or $self->uri ne 'about:blank')) {
    #    # We need to fake the content headers from <meta> tags too...
    #    # Maybe this even needs to go into ->get()
    #    $res->code( 200 );
    #} else {
    #    $res->code( 400 ); # Must have been "not found"
    #};
    $res
}

sub httpRequestFromChromeRequest( $self, $event ) {
    my $req = HTTP::Request->new(
        $event->{params}->{request}->{method},
        $event->{params}->{request}->{url},
        HTTP::Headers->new( %{ $event->{params}->{request}->{headers}} ),
    );
};

=head2 C<< $mech->getRequestPostData >>

    if( $info->{params}->{response}->{requestHeaders}->{":method"} eq 'POST' ) {
        $req->{postBody} = $m->getRequestPostData( $id );
    };

Retrieves the data sent with a POST request

=cut

sub getRequestPostData_future( $self, $requestId ) {
    $self->log('debug', "Fetching request POST body for $requestId");
    weaken( my $s = $self );
    return
        $self->driver->send_message('Network.getRequestPostData', requestId => $requestId)
        ->then(sub {
        $s->log('trace', "Have POST body", @_);
        my ($body_obj) = @_;

        my $body = $body_obj->{postData};
        # WTF? The documentation says the body is base64 encoded, but
        # experimentation shows it isn't, at least for JSON content :-/
        #$body = decode_base64( $body );
        Future->done( $body )
    });
}

sub getRequestPostData( $self, $requestId ) {
    $self->getRequestPostData_future( $requestId )->get
}

sub getResponseBody( $self, $requestId ) {
    $self->log('debug', "Fetching response body for $requestId");
    my $s = $self;
    weaken $s;
    return
        $self->driver->send_message('Network.getResponseBody', requestId => $requestId)
        ->then(sub {
        $s->log('debug', "Have body", @_);
        my ($body_obj) = @_;

        my $body = $body_obj->{body};
        $body = decode_base64( $body )
            if $body_obj->{base64Encoded};
        Future->done( $body )
    });
}

sub httpResponseFromChromeResponse( $self, $res ) {
    my $response = HTTP::Response->new(
        $res->{params}->{response}->{status} || 200, # is 0 for files?!
        $res->{params}->{response}->{statusText},
        HTTP::Headers->new( %{ $res->{params}->{response}->{headers} }),
    );
    $self->log('debug',sprintf "Status %0d - %s",$response->code, $response->status_line);

    # Also fetch the response body and include it in the response
    # as we can't do that lazily...
    # This is nasty, as we will fill in the response lazily and the user has
    # no way of knowing when we have filled in the response body
    # The proper way might be to return a proxy object...
    my $requestId = $res->{params}->{requestId};

    if( $requestId ) {
        my $full_response_future;

        my $s = $self;
        weaken $s;
        $full_response_future = $self->getResponseBody( $requestId )->then( sub( $body ) {
            $s->log('debug', "Response body arrived");
            $response->content( $body );
            undef $full_response_future;
            Future->done
        });
        #$response->content_ref( \$body );
    };
    $response
};

sub httpResponseFromChromeNetworkFail( $self, $res ) {
    my $response = HTTP::Response->new(
        $res->{params}->{response}->{status} || 599, # No error code exists for files
        $res->{params}->{response}->{errorText},
        HTTP::Headers->new(),
    );
};

sub httpResponseFromChromeUrlUnreachable( $self, $res ) {
    my $response = HTTP::Response->new(
        599, # No error code exists for files
        "Unreachable URL: " . $res->{params}->{frame}->{unreachableUrl},
        HTTP::Headers->new(),
    );
};

sub httpMessageFromEvents( $self, $frameId, $events, $url ) {
    my ($requestId,$loaderId);

    if( $url ) {
        # Find the request id of the request
        for( @$events ) {
            if( $_->{method} eq 'Network.requestWillBeSent' and $_->{params}->{frameId} eq $frameId ) {
                if( $url and $_->{params}->{request}->{url} eq $url ) {
                    $requestId = $_->{params}->{requestId};
                } else {
                    $requestId ||= $_->{params}->{requestId};
                };
            }
        };
    };

    # Just silence some undef warnings
    if( ! defined $requestId) {
        $requestId = ''
    };
    if( ! defined $frameId) {
        $frameId = ''
    };

    my @events = grep {
        my $this_frame =    (exists $_->{params}->{frameId} && $_->{params}->{frameId})
                         || (exists $_->{params}->{frame}->{id} && $_->{params}->{frame}->{id});
        if(     exists $_->{params}->{requestId}
            and $_->{params}->{requestId} eq $requestId
        ) {
            "Matches our request id"
        } elsif( ! exists $_->{params}->{requestId}
                 and $this_frame eq $frameId
        ) {
            "Matches our frame id and has no associated request"
        } else {
            ""
        }

    } map {
        # Extract the loaderId and requestId, if we haven't found it yet
        if( $_->{method} eq 'Network.requestWillBeSent' and $_->{params}->{frameId} eq $frameId ) {
            $requestId ||= $_->{params}->{requestId};
            $loaderId ||= $_->{params}->{loaderId};
            $requestId ||= $_->{params}->{requestId};
        };
        $_
    } @$events;

    my %events;
    for (@events) {
        #warn join " - ", $_->{method}, $_->{params}->{loaderId}, $_->{params}->{frameId};
        $events{ $_->{method} } ||= $_;
    };

    # Create HTTP::Request object from 'Network.requestWillBeSent'
    my $request;
    my $response;

    my $about_blank_loaded =    $events{ "Page.frameNavigated" }
                             && $events{ "Page.frameNavigated" }->{params}->{frame}->{url} eq 'about:blank';
    if( $about_blank_loaded ) {
    #warn "About:blank";
        $response = HTTP::Response->new(
            200,
            'OK',
        );
    } elsif ( my $res = $events{ 'Network.responseReceived' }) {
    #warn "Network.responseReceived";
            $response = $self->httpResponseFromChromeResponse( $res );
            $response->request( $request );

    } elsif ( $res = $events{ 'Page.navigatedWithinDocument' }) {
        # A fake response, just in case anybody checks
        $response = HTTP::Response->new(
            200, # is 0 for files?!
            "OK",
            HTTP::Headers->new(),
        );
        $response->request( $request );

    } elsif( $res = $events{ 'Network.loadingFailed' }) {
    #warn "Network.loadingFailed";
        $response = $self->httpResponseFromChromeNetworkFail( $res );
        $response->request( $request );

    } elsif ( $res = $events{ 'Page.frameNavigated' }
              and $res->{params}->{frame}->{unreachableUrl}) {
    #warn "Network.frameNavigated (unreachable)";
        $response = $self->httpResponseFromChromeUrlUnreachable( $res );
        $response->request( $request );

    } elsif ( $res = $events{ 'Page.frameNavigated' }
              and $res->{params}->{frame}->{url} =~ m!^file://!) {
    #warn "Network.frameNavigated (file)";
        # Chrome v67+ doesn't send network events for file:// navigation
        $response = HTTP::Response->new(
            200, # is 0 for files?!
            "OK",
            HTTP::Headers->new(),
        );
        $response->request( $request );

    } elsif ( $res = $events{ 'Page.frameStoppedLoading' }
              and $res->{params}->{frameId} eq $frameId) {
    #warn "Network.frameStoppedLoading";
        # Chrome v67+ doesn't send network events for file:// navigation
        # so we need to fake it completely
        $response = HTTP::Response->new(
            200, # is 0 for files?!
            "OK",
            HTTP::Headers->new(),
        );
        $response->request( $request );

    } elsif( $res = $events{ "MechanizeChrome.download" } ) {
    #warn "MechanizeChrome.download";
        $response = HTTP::Response->new(
            $res->{params}->{response}->{status} || 200, # is 0 for files?!
            $res->{params}->{response}->{statusText},
            HTTP::Headers->new( %{ $res->{params}->{response}->{headers} }),
        )

    } else {
        require Data::Dumper;
        warn Data::Dumper::Dumper( $events );
        die join " ", "Chrome behaviour problem: Didn't see a",
                      "'Network.responseReceived' event for frameId $frameId,",
                      "requestId $requestId, cannot synthesize response.",
                      "I saw " . join ",", sort keys %events;
    };
    $response
}

=head2 C<< $mech->post( $url, %options ) >>

B<not implemented>

  $mech->post( 'http://example.com',
      params => { param => "Hello World" },
      headers => {
        "Content-Type" => 'application/x-www-form-urlencoded',
      },
      charset => 'utf-8',
  );

Sends a POST request to C<$url>.

A C<Content-Length> header will be automatically calculated if
it is not given.

The following options are recognized:

=over 4

=item *

C<headers> - a hash of HTTP headers to send. If not given,
the content type will be generated automatically.

=item *

C<data> - the raw data to send, if you've encoded it already.

=back

=cut

sub post {
    my ($self, $url, %options) = @_;
    #my $b = $self->tab->{linkedBrowser};
    $self->clear_current_form;

    #my $flags = 0;
    #if ($options{no_cache}) {
    #  $flags = $self->repl->constant('nsIWebNavigation.LOAD_FLAGS_BYPASS_CACHE');
    #};

    # If we don't have data, encode the parameters:
    if( !$options{ data }) {
        my $req= HTTP::Request::Common::POST( $url, $options{params} );
        #warn $req->content;
        carp "Faking content from parameters is not yet supported.";
        #$options{ data } = $req->content;
    };

    #$options{ charset } ||= 'utf-8';
    #$options{ headers } ||= {};
    #$options{ headers }->{"Content-Type"} ||= "application/x-www-form-urlencoded";
    #if( $options{ charset }) {
    #    $options{ headers }->{"Content-Type"} .= "; charset=$options{ charset }";
    #};

    # Javascript POST implementation taken from
    # http://stackoverflow.com/questions/133925/javascript-post-request-like-a-form-submit
    $self->eval(<<'JS', $url, $options{ params }, 'POST');
        function (path, params, method) {
            method = method || "post"; // Set method to post by default if not specified.

            // The rest of this code assumes you are not using a library.
            // It can be made less wordy if you use one.
            var form = document.createElement("form");
            form.setAttribute("method", method);
            form.setAttribute("action", path);

            for(var key in params) {
                if(params.hasOwnProperty(key)) {
                    var hiddenField = document.createElement("input");
                    hiddenField.setAttribute("type", "hidden");
                    hiddenField.setAttribute("name", key);
                    hiddenField.setAttribute("value", params[key]);

                    form.appendChild(hiddenField);
                 }
            }

            document.body.appendChild(form);
            form.submit();
        }
JS
    # Now, how to trick Selenium into fetching the response?
}

=head2 C<< $mech->reload( %options ) >>

  $mech->reload( ignoreCache => 1 )

Acts like the reload button in a browser: repeats the current request.
The history (as per the "back" method) is not altered.

Returns the HTTP::Response object from the reload, or undef if there's no
current request.

=cut

sub reload( $self, %options ) {
    $self->_mightNavigate( sub {
        $self->driver->send_message('Page.reload', %options )
    }, navigates => 1, %options)
    ->get;
}

=head2 C<< $mech->set_download_directory( $dir ) >>

    my $downloads = tempdir();
    $mech->set_download_directory( $downloads );

Enables automatic file downloads and sets the directory where the files
will be downloaded to. Setting this to undef will disable downloads again.

The directory in C<$dir> must be an absolute path, since Chrome does not know
about the current directory of your Perl script.

=cut

sub set_download_directory_future( $self, $dir="" ) {
    $self->{download_directory} = $dir;
    if( "" eq $dir ) {
        $self->driver->send_message('Page.setDownloadBehavior',
            behavior => 'deny',
        )
    } else {
        $self->driver->send_message('Page.setDownloadBehavior',
            behavior => 'allow',
            downloadPath => $dir
        )
    };
};

sub set_download_directory( $self, $dir="" ) {
    $self->set_download_directory_future($dir)->get
};

=head2 C<< $mech->cookie_jar >>

    my $cookies = $mech->cookie_jar

Returns all the Chrome cookies in a L<HTTP::Cookies::ChromeDevTools> instance.
Setting a cookie in there will also set the cookie in Chrome.

=cut

sub cookie_jar( $self ) {
    $self->{cookie_jar} ||= do {
        my $c = HTTP::Cookies::ChromeDevTools->new( driver => $self->driver );
        $c->load;
        $c
    };
};

=head2 C<< $mech->add_header( $name => $value, ... ) >>

    $mech->add_header(
        'X-WWW-Mechanize-Chrome' => "I'm using it",
        Encoding => 'text/klingon',
    );

This method sets up custom headers that will be sent with B<every> HTTP(S)
request that Chrome makes.

Note that currently, we only support one value per header.

=cut

sub _set_extra_headers_future( $self, %headers ) {
    $self->log('debug',"Setting additional headers", \%headers);
    $self->driver->send_message('Network.setExtraHTTPHeaders',
        headers => \%headers
    );
};

sub _set_extra_headers( $self, %headers ) {
    $self->_set_extra_headers_future(
        %headers
    )->get;
};

sub add_header( $self, %headers ) {
    $self->{ extra_headers } = {
        %{ $self->{ extra_headers } },
        %headers,
    };
    $self->_set_extra_headers( %{ $self->{ extra_headers } } );
};

=head2 C<< $mech->delete_header( $name , $name2... ) >>

    $mech->delete_header( 'User-Agent' );

Removes HTTP headers from the agent's list of special headers. Note
that Chrome may still send a header with its default value.

=cut

sub delete_header( $self, @headers ) {
    delete @{ $self->{ extra_headers } }{ @headers };
    $self->_set_extra_headers( %{ $self->{ extra_headers } } );
};

=head2 C<< $mech->reset_headers >>

    $mech->reset_headers();

Removes all custom headers and makes Chrome send its defaults again.

=cut

sub reset_headers( $self ) {
    $self->{ extra_headers } = {};
    $self->_set_extra_headers();
};

=head2 C<< $mech->block_urls() >>

    $mech->block_urls( '//facebook.com/js/conversions/tracking.js' );

Sets the list of blocked URLs. These URLs will not be retrieved by Chrome
when loading a page. This is useful to eliminate tracking images or to test
resilience in face of bad network conditions.

=cut

sub block_urls( $self, @urls ) {
    $self->driver->send_message( 'Network.setBlockedURLs',
        urls => \@urls
    )->get;
}

=head2 C<< $mech->res() >> / C<< $mech->response(%options) >>

    my $response = $mech->response(headers => 0);

Returns the current response as a L<HTTP::Response> object.

=cut

sub response( $self ) {
    $self->{response}
};

{
    no warnings 'once';
    *res = \&response;
}

# Call croak or log it, depending on the C< autodie > setting
sub signal_condition {
    my ($self,$msg) = @_;
    if ($self->{autodie}) {
        croak $msg
    } else {
        $self->log( 'warn', $msg );
    }
};

# Call croak on the C< autodie > setting if we have a non-200 status
sub signal_http_status {
    my ($self) = @_;
    if ($self->{autodie}) {
        if ($self->status and $self->status !~ /^2/ and $self->status != 0) {
            # there was an error
            croak ($self->response()->message || sprintf "Got status code %d", $self->status );
        };
    } else {
        # silent
    }
};

=head2 C<< $mech->success() >>

    $mech->get('https://google.com');
    print "Yay"
        if $mech->success();

Returns a boolean telling whether the last request was successful.
If there hasn't been an operation yet, returns false.

This is a convenience function that wraps C<< $mech->res->is_success >>.

=cut

sub success {
    my $res = $_[0]->response();
    $res and $res->is_success
}

=head2 C<< $mech->status() >>

    $mech->get('https://google.com');
    print $mech->status();
    # 200

Returns the HTTP status code of the response.
This is a 3-digit number like 200 for OK, 404 for not found, and so on.

=cut

sub status {
    my ($self) = @_;
    return $self->response()->code
};

=head2 C<< $mech->back() >>

    $mech->back();

Goes one page back in the page history.

Returns the (new) response.

=cut

sub back( $self, %options ) {
    $self->_mightNavigate( sub {
        $self->driver->send_message('Page.getNavigationHistory')->then(sub($history) {
            my $entry = $history->{entries}->[ $history->{currentIndex}-1 ];
            $self->driver->send_message('Page.navigateToHistoryEntry', entryId => $entry->{id})
        });
    }, navigates => 1, %options)
    ->get;
};

=head2 C<< $mech->forward() >>

    $mech->forward();

Goes one page forward in the page history.

Returns the (new) response.

=cut

sub forward( $self, %options ) {
    $self->_mightNavigate( sub {
        $self->driver->send_message('Page.getNavigationHistory')->then(sub($history) {
            my $entry = $history->{entries}->[ $history->{currentIndex}+1 ];
            $self->driver->send_message('Page.navigateToHistoryEntry', entryId => $entry->{id})
        });
    }, navigates => 1, %options)
    ->get;
}

=head2 C<< $mech->stop() >>

    $mech->stop();

Stops all loading in Chrome, as if you pressed C<ESC>.

This function is mostly of use in callbacks or in a timer callback from your
event loop.

=cut

sub stop( $self ) {
    $self->driver->send_message('Page.stopLoading')->get;
}

=head2 C<< $mech->uri() >>

    print "We are at " . $mech->uri;

Returns the current document URI.

=cut

sub uri( $self ) {
    my $d = $self->document;
    URI->new( $d->{root}->{documentURL} )
}

=head2 C<< $mech->infinite_scroll( [$wait_time_in_seconds] ) >>

    $new_content_found = $mech->infinite_scroll(3);

Loads content into pages that have "infinite scroll" capabilities by scrolling
to the bottom of the web page and waiting up to the number of seconds, as set by
the optional C<$wait_time_in_seconds> argument, for the browser to load more
content. The default is to wait up to 20 seconds. For reasonbly fast sites,
the wait time can be set much lower.

The method returns a boolean C<true> if new content is loaded, C<false>
otherwise. You can scroll to the end (if there is one) of an infinitely
scrolling page like so:

    while( $mech->infinite_scroll ) {
        # Tests for exiting the loop earlier
        last if $count++ >= 10;
    }

=cut

sub infinite_scroll {
    my $self        = shift;
    my $wait_time   = shift || 20;

    my $current_height = $self->_get_body_height;
    $self->log('debug', "Current page body height: $current_height");

    $self->_scroll_to_bottom;

    my $new_height = $self->_get_body_height;
    $self->log('debug', "New page body height: $new_height");

    my $start_time = time();
    while (!($new_height > $current_height)) {

        # wait for new elements to load until $wait_time is reached
        if (time() - $start_time > $wait_time) {
          return 0;
        }

        # wait 1/10th sec for new elements to load
        usleep 100000;
        $new_height = $self->_get_body_height;
    }
    return 1;
}

sub _get_body_height {
    my $self = shift;

    my ($height) = $self->eval( 'document.body.scrollHeight' );
    return $height;
}

sub _scroll_to_bottom {
    my $self = shift;

    # scroll to bottom and wait for some content to load
    $self->eval( 'window.scroll(0,document.body.scrollHeight + 200)' );
    usleep 100000;
}

=head1 CONTENT METHODS

=head2 C<< $mech->document_future() >>

=head2 C<< $mech->document() >>

    print $self->document->{nodeId};

This is WWW::Mechanize::Chrome specific.

=cut

sub document_future( $self ) {
    $self->driver->send_message( 'DOM.getDocument' )
}

sub document( $self ) {
    $self->document_future->get
}

sub decoded_content($self) {
    $self->document_future->then(sub( $root ) {
        # Join _all_ child nodes together to also fetch DOCTYPE nodes
        # and the stuff that comes after them
        my @content = map {
            my $nodeId = $_->{nodeId};
            $self->log('trace', "Fetching HTML for node " . $nodeId );
            $self->driver->send_message('DOM.getOuterHTML', nodeId => 0+$nodeId )
        } @{ $root->{root}->{children} };

        Future->wait_all( @content )
    })->then( sub( @outerHTML_f ) {
        Future->done( join "", map { $_->get->{outerHTML} } @outerHTML_f )
    })->get;
};

=head2 C<< $mech->content( %options ) >>

  print $mech->content;
  print $mech->content( format => 'html' ); # default
  print $mech->content( format => 'text' ); # identical to ->text

This always returns the content as a Unicode string. It tries
to decode the raw content according to its input encoding.
This currently only works for HTML pages, not for images etc.

Recognized options:

=over 4

=item *

C<format> - the stuff to return

The allowed values are C<html> and C<text>. The default is C<html>.

=back

=cut

sub content( $self, %options ) {
    $options{ format } ||= 'html';
    my $format = delete $options{ format };

    my $content;
    if( 'html' eq $format ) {
        $content= $self->decoded_content()
    } elsif ( $format eq 'text' ) {
        $content= $self->text;
    } else {
        $self->die( qq{Unknown "format" parameter "$format"} );
    };
};

=head2 C<< $mech->text() >>

    print $mech->text();

Returns the text of the current HTML content.  If the content isn't
HTML, $mech will die.

=cut

sub text {
    my $self = shift;

    # Waugh - this is highly inefficient but conveniently short to write
    # Maybe this should skip SCRIPT nodes...
    join '', map { $_->get_text() } $self->xpath('//*/text()');
}

=head2 C<< $mech->content_encoding() >>

    print "The content is encoded as ", $mech->content_encoding;

Returns the encoding that the content is in. This can be used
to convert the content from UTF-8 back to its native encoding.

=cut

sub content_encoding {
    my ($self) = @_;
    # Let's trust the <meta http-equiv first, and the header second:
    # Also, a pox on Chrome for not having lower-case or upper-case
    if(( my $meta )= $self->xpath( q{//meta[translate(@http-equiv,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')="content-type"]}, first => 1 )) {
        (my $ct= $meta->{attributes}->{'content'}) =~ s/^.*;\s*charset=\s*//i;
        return $ct
            if( $ct );
    };
    $self->response->header('Content-Type');
};

=head2 C<< $mech->update_html( $html ) >>

  $mech->update_html($html);

Writes C<$html> into the current document. This is mostly
implemented as a convenience method for L<HTML::Display::MozRepl>.

The value passed in as C<$html> will be stringified.

=cut

sub update_html( $self, $content ) {
    $self->document_future->then(sub( $root ) {
        # Find "HTML" child node:
        my $nodeId = $root->{root}->{children}->[0]->{nodeId};
        $self->log('trace', "Setting HTML for node " . $nodeId );
        $self->driver->send_message('DOM.setOuterHTML', nodeId => 0+$nodeId, outerHTML => "$content" )
     })->get;
};

=head2 C<< $mech->base() >>

  print $mech->base;

Returns the URL base for the current page.

The base is either specified through a C<base>
tag or is the current URL.

This method is specific to WWW::Mechanize::Chrome.

=cut

sub base {
    my ($self) = @_;
    (my $base) = $self->selector('base');
    $base = $base->get_attribute('href')
        if $base;
    $base ||= $self->uri;
};

=head2 C<< $mech->content_type() >>

=head2 C<< $mech->ct() >>

  print $mech->content_type;

Returns the content type of the currently loaded document

=cut

sub content_type {
    my ($self) = @_;
    # Let's trust the <meta http-equiv first, and the header second:
    # Also, a pox on Chrome for not having lower-case or upper-case
    my $ct;
    if(my( $meta )= $self->xpath( q{//meta[translate(@http-equiv,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')="content-type"]}, first => 1 )) {
        $ct= $meta->{attributes}->{'content'};
    };
    if(!$ct and my $r= $self->response ) {

        my $h= $r->headers;
        $ct= $h->header('Content-Type');
    };
    $ct =~ s/;.*$// if defined $ct;
    $ct
};

{
    no warnings 'once';
    *ct = \&content_type;
}

=head2 C<< $mech->is_html() >>

  print $mech->is_html();

Returns true/false on whether our content is HTML, according to the
HTTP headers.

=cut

sub is_html {
    my $self = shift;
    return defined $self->ct && ($self->ct eq 'text/html');
}

=head2 C<< $mech->title() >>

  print "We are on page " . $mech->title;

Returns the current document title.

=cut

sub title( $self ) {
    #if( $self->tab ) {
    #    my $id = $self->tab->{id};
    #    (my $tab_now) = grep { $_->{id} eq $id } $self->driver->list_tabs->get;
    #    return $tab_now->{title};
    #} else {
        $self->target->info->{title}
    #}
};

=head1 EXTRACTION METHODS

=head2 C<< $mech->links() >>

  print $_->text . " -> " . $_->url . "\n"
      for $mech->links;

Returns all links in the document as L<WWW::Mechanize::Link> objects.

Currently accepts no parameters. See C<< ->xpath >>
or C<< ->selector >> when you want more control.

=cut

our %link_spec = (
    a      => { url => 'href', },
    area   => { url => 'href', },
    frame  => { url => 'src', },
    iframe => { url => 'src', },
    link   => { url => 'href', },
    meta   => { url => 'content', xpath => (join '',
                    q{translate(@http-equiv,'ABCDEFGHIJKLMNOPQRSTUVWXYZ',},
                    q{'abcdefghijklmnopqrstuvwxyz')="refresh"}), },
);
# taken from WWW::Mechanize. This should possibly just be reused there
sub make_link {
    my ($self,$node,$base) = @_;

    my $tag = lc $node->get_tag_name;
    my $url;
    if ($tag) {
        if( ! exists $link_spec{ $tag }) {
            carp "Unknown link-spec tag '$tag'";
            $url= '';
        } else {
            $url = $node->get_attribute( $link_spec{ $tag }->{url} );
        };
    };

    if ($tag eq 'meta') {
        my $content = $url;
        if ( $content =~ /^\d+\s*;\s*url\s*=\s*(\S+)/i ) {
            $url = $1;
            $url =~ s/^"(.+)"$/$1/ or $url =~ s/^'(.+)'$/$1/;
        }
        else {
            undef $url;
        }
    };

    if (defined $url) {
        my $res = WWW::Mechanize::Link->new({
            tag   => $tag,
            name  => $node->get_attribute('name'),
            base  => $base,
            url   => $url,
            text  => $node->get_attribute('innerHTML'),
            attrs => {},
        });

        return $res
    } else {
        ()
    };
}

sub links {
    my ($self) = @_;
    my @links = $self->selector( join ",", sort keys %link_spec);
    my $base = $self->base;
    return map {
        $self->make_link($_,$base)
    } @links;
};

=head2 C<< $mech->selector( $css_selector, %options ) >>

  my @text = $mech->selector('p.content');

Returns all nodes matching the given CSS selector. If
C<$css_selector> is an array reference, it returns
all nodes matched by any of the CSS selectors in the array.

This takes the same options that C<< ->xpath >> does.

This method is implemented via L<WWW::Mechanize::Plugin::Selector>.

=cut

sub selector {
    my ($self,$query,%options) = @_;
    $options{ user_info } ||= "CSS selector '$query'";
    if ('ARRAY' ne (ref $query || '')) {
        $query = [$query];
    };
    my $root = $options{ node } ? './' : '';
    my @q = map { selector_to_xpath($_, root => $root) } @$query;
    $self->xpath(\@q, %options);
};

=head2 C<< $mech->find_link_dom( %options ) >>

  print $_->{innerHTML} . "\n"
      for $mech->find_link_dom( text_contains => 'CPAN' );

A method to find links, like L<WWW::Mechanize>'s
C<< ->find_links >> method. This method returns DOM objects from
Chrome instead of WWW::Mechanize::Link objects.

Note that Chrome
might have reordered the links or frame links in the document
so the absolute numbers passed via C<n>
might not be the same between
L<WWW::Mechanize> and L<WWW::Mechanize::Chrome>.

The supported options are:

=over 4

=item *

C<< text >> and C<< text_contains >> and C<< text_regex >>

Match the text of the link as a complete string, substring or regular expression.

Matching as a complete string or substring is a bit faster, as it is
done in the XPath engine of Chrome.

=item *

C<< id >> and C<< id_contains >> and C<< id_regex >>

Matches the C<id> attribute of the link completely or as part

=item *

C<< name >> and C<< name_contains >> and C<< name_regex >>

Matches the C<name> attribute of the link

=item *

C<< url >> and C<< url_regex >>

Matches the URL attribute of the link (C<href>, C<src> or C<content>).

=item *

C<< class >> - the C<class> attribute of the link

=item *

C<< n >> - the (1-based) index. Defaults to returning the first link.

=item *

C<< single >> - If true, ensure that only one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

=item *

C<< one >> - If true, ensure that at least one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

The method C<croak>s if no link is found. If the C<single> option is true,
it also C<croak>s when more than one link is found.

=back

=cut

use vars '%xpath_quote';
%xpath_quote = (
    '"' => '\"',
    #"'" => "\\'",
    #'[' => '&#91;',
    #']' => '&#93;',
    #'[' => '[\[]',
    #'[' => '\[',
    #']' => '[\]]',
);

sub quote_xpath($) {
    local $_ = $_[0];
    s/(['"\[\]])/$xpath_quote{$1} || $1/ge;
    $_
};

sub find_link_dom {
    my ($self,%opts) = @_;
    my %xpath_options;

    for (qw(node document frames)) {
        # Copy over XPath options that were passed in
        if (exists $opts{ $_ }) {
            $xpath_options{ $_ } = delete $opts{ $_ };
        };
    };

    my $single = delete $opts{ single };
    my $one = delete $opts{ one } || $single;
    if ($single and exists $opts{ n }) {
        croak "It doesn't make sense to use 'single' and 'n' option together"
    };
    my $n = (delete $opts{ n } || 1);
    $n--
        if ($n ne 'all'); # 1-based indexing
    my @spec;

    # Decode text and text_contains into XPath
    for my $lvalue (qw( text id name class )) {
        my %lefthand = (
            text => 'text()',
        );
        my %match_op = (
            '' => q{%s="%s"},
            'contains' => q{contains(%s,"%s")},
            # Ideally we would also handle *_regex here, but Chrome XPath
            # does not support fn:matches() :-(
            #'regex' => q{matches(%s,"%s","%s")},
        );
        my $lhs = $lefthand{ $lvalue } || '@'.$lvalue;
        for my $op (keys %match_op) {
            my $v = $match_op{ $op };
            $op = '_'.$op if length($op);
            my $key = "${lvalue}$op";

            if (exists $opts{ $key }) {
                my $p = delete $opts{ $key };
                push @spec, sprintf $v, $lhs, $p;
            };
        };
    };

    if (my $p = delete $opts{ url }) {
        push @spec, sprintf '@href = "%s" or @src="%s"', quote_xpath $p, quote_xpath $p;
    }
    my @tags = (sort keys %link_spec);
    if (my $p = delete $opts{ tag }) {
        @tags = $p;
    };
    if (my $p = delete $opts{ tag_regex }) {
        @tags = grep /$p/, @tags;
    };
    my $q = join '|',
            map {
                my $xp= exists $link_spec{ $_ } ? $link_spec{$_}->{xpath} : undef;
                my @full = map {qq{($_)}} grep {defined} (@spec, $xp);
                if (@full) {
                    sprintf "//%s[%s]", $_, join " and ", @full;
                } else {
                    sprintf "//%s", $_
                };
            }  (@tags);
    #warn $q;

    my @res = $self->xpath($q, %xpath_options );

    if (keys %opts) {
        # post-filter the remaining links through WWW::Mechanize
        # for all the options we don't support with XPath

        my $base = $self->base;
        require WWW::Mechanize;
        @res = grep {
            WWW::Mechanize::_match_any_link_parms($self->make_link($_,$base),\%opts)
        } @res;
    };

    if ($one) {
        if (0 == @res) { $self->signal_condition( "No link found matching '$q'" )};
        if ($single) {
            if (1 <  @res) {
                $self->highlight_node(@res);
                $self->signal_condition(
                    sprintf "%d elements found found matching '%s'", scalar @res, $q
                );
            };
        };
    };

    if ($n eq 'all') {
        return @res
    };
    $res[$n]
}

=head2 C<< $mech->find_link( %options ) >>

  print $_->text . "\n"
      for $mech->find_link( text_contains => 'CPAN' );

A method quite similar to L<WWW::Mechanize>'s method.
The options are documented in C<< ->find_link_dom >>.

Returns a L<WWW::Mechanize::Link> object.

This defaults to not look through child frames.

=cut

sub find_link {
    my ($self,%opts) = @_;
    my $base = $self->base;
    croak "Option 'all' not available for ->find_link. Did you mean to call ->find_all_links()?"
        if 'all' eq ($opts{n} || '');
    if (my $link = $self->find_link_dom(frames => 0, %opts)) {
        return $self->make_link($link, $base)
    } else {
        return
    };
};

=head2 C<< $mech->find_all_links( %options ) >>

  print $_->text . "\n"
      for $mech->find_all_links( text_regex => qr/google/i );

Finds all links in the document.
The options are documented in C<< ->find_link_dom >>.

Returns them as list or an array reference, depending
on context.

This defaults to not look through child frames.

=cut

sub find_all_links {
    my ($self, %opts) = @_;
    $opts{ n } = 'all';
    my $base = $self->base;
    my @matches = map {
        $self->make_link($_, $base);
    } $self->find_all_links_dom( frames => 0, %opts );
    return @matches if wantarray;
    return \@matches;
};

=head2 C<< $mech->find_all_links_dom %options >>

  print $_->{innerHTML} . "\n"
      for $mech->find_all_links_dom( text_regex => qr/google/i );

Finds all matching linky DOM nodes in the document.
The options are documented in C<< ->find_link_dom >>.

Returns them as list or an array reference, depending
on context.

This defaults to not look through child frames.

=cut

sub find_all_links_dom {
    my ($self,%opts) = @_;
    $opts{ n } = 'all';
    my @matches = $self->find_link_dom( frames => 0, %opts );
    return @matches if wantarray;
    return \@matches;
};

=head2 C<< $mech->follow_link( $link ) >>

=head2 C<< $mech->follow_link( %options ) >>

  $mech->follow_link( xpath => '//a[text() = "Click here!"]' );

Follows the given link. Takes the same parameters that C<find_link_dom>
uses.

Note that C<< ->follow_link >> will only try to follow link-like
things like C<A> tags.

=cut

sub follow_link {
    my ($self,$link,%opts);
    if (@_ == 2) { # assume only a link parameter
        ($self,$link) = @_;
        $self->click($link);
    } else {
        ($self,%opts) = @_;
        _default_limiter( one => \%opts );
        $link = $self->find_link_dom(%opts);
        $self->click({ dom => $link, %opts });
    }
}

sub activate_parent_container {
    my( $self, $doc )= @_;
    $self->activate_container( $doc, 1 );
};

sub activate_container {
    my( $self, $doc, $just_parent )= @_;
    my $driver= $self->driver;

    if( ! $doc->{__path}) {
        die "Invalid document without __path encountered. I'm sorry.";
    };
    # Activate the root window/frame
    #warn "Activating root frame:";
    #$driver->switch_to_frame();
    #warn "Activating root frame done.";

    for my $el ( @{ $doc->{__path} }) {
        #warn "Switching frames downwards ($el)";
        #warn "Tag: " . $el->get_tag_name;
        #warn Dumper $el;
        warn sprintf "Switching during path to %s %s", $el->get_tag_name, $el->get_attribute('src');
        $driver->switch_to_frame( $el );
    };

    if( ! $just_parent ) {
        warn sprintf "Activating container %s too", $doc->{id};
        # Now, unless it's the root frame, activate the container. The root frame
        # already is activated above.
        warn "Getting tag";
        my $tag= $doc->get_tag_name;
        #my $src= $doc->get_attribute('src');
        if( 'html' ne $tag and '' ne $tag) {
            #warn sprintf "Switching to final container %s %s", $tag, $src;
            $driver->switch_to_frame( $doc );
        };
        #warn sprintf "Switched to final/main container %s %s", $tag, $src;
    };
    #warn $self->driver->get_current_url;
    #warn $self->driver->get_title;
    #my $body= $doc->get_attribute('contentDocument');
    my $body= $driver->find_element('/*', 'xpath');
    if( $body ) {
        warn "Now active container: " . $body->get_attribute('innerHTML');
        #$body= $body->get_attribute('document');
        #warn $body->get_attribute('innerHTML');
    };
};

=head2 C<< $mech->xpath( $query, %options ) >>

    my $link = $mech->xpath('//a[id="clickme"]', one => 1);
    # croaks if there is no link or more than one link found

    my @para = $mech->xpath('//p');
    # Collects all paragraphs

    my @para_text = $mech->xpath('//p/text()', type => $mech->xpathResult('STRING_TYPE'));
    # Collects all paragraphs as text

Runs an XPath query in Chrome against the current document.

If you need more information about the returned results,
use the C<< ->xpathEx() >> function.

The options allow the following keys:

=over 4

=item *

C<< document >> - document in which the query is to be executed. Use this to
search a node within a specific subframe of C<< $mech->document >>.

=item *

C<< frames >> - if true, search all documents in all frames and iframes.
This may or may not conflict with C<node>. This will default to the
C<frames> setting of the WWW::Mechanize::Chrome object.

=item *

C<< node >> - node relative to which the query is to be executed. Note
that you will have to use a relative XPath expression as well. Use

  .//foo

instead of

  //foo

=item *

C<< single >> - If true, ensure that only one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

=item *

C<< one >> - If true, ensure that at least one element is found. Otherwise croak
or carp, depending on the C<autodie> parameter.

=item *

C<< maybe >> - If true, ensure that at most one element is found. Otherwise
croak or carp, depending on the C<autodie> parameter.

=item *

C<< all >> - If true, return all elements found. This is the default.
You can use this option if you want to use C<< ->xpath >> in scalar context
to count the number of matched elements, as it will otherwise emit a warning
for each usage in scalar context without any of the above restricting options.

=item *

C<< any >> - no error is raised, no matter if an item is found or not.

=back

Returns the matched results as L<WWW::Mechanize::Chrome::Node> objects.

You can pass in a list of queries as an array reference for the first parameter.
The result will then be the list of all elements matching any of the queries.

This is a method that is not implemented in WWW::Mechanize.

In the long run, this should go into a general plugin for
L<WWW::Mechanize>.

=cut

sub _performSearch( $self, %args ) {
    my $backendNodeId = $args{ backendNodeId };
    my $query = $args{ query };
    $self->driver->send_message( 'DOM.performSearch', query => $query )->then(sub($results) {

        if( $results->{resultCount} ) {
            my $searchResults;
            my $searchId = $results->{searchId};
            my @childNodes;
            my $setChildNodes = $self->add_listener('DOM.setChildNodes', sub( $ev ) {
                push @childNodes, @{ $ev->{params}->{nodes} };
            });
            $self->driver->send_message( 'DOM.getSearchResults',
                searchId => $results->{searchId},
                fromIndex => 0,
                toIndex => $results->{resultCount}
            # We can't immediately discard our search results until we find out
            # what invalidates node ids.
            # So we currently accumulate memory until we disconnect. Oh well.
            # And node ids still get invalidated
            #)->followed_by( sub( $results ) {
            #    $searchResults = $results->get;
            #    $self->driver->send_message( 'DOM.discardSearchResults',
            #        searchId => $searchId,
            #    );
            #}
            )->then( sub( $response ) {
                # This should already happen through the DESTROY callback
                # but we'll be explicit here
                $setChildNodes->unregister;
                undef $setChildNodes;
                my %nodes = map {
                    $_->{nodeId} => $_
                } @childNodes;

                # Filter @found for those nodes that have $nodeId as
                # ancestor because we can't restrict the search in Chrome
                # directly...
                my @foundNodes = @{ $response->{nodeIds} };
                if( $backendNodeId ) {
                    $self->log('trace', "Filtering query results for ancestor backendNodeId $backendNodeId");
                    @foundNodes = grep {
                        my $p = $nodes{ $_ };
                        while( $p and $p->{backendNodeId} != $backendNodeId ) {
                            $p = $nodes{ $p->{parentId} };
                        };
                        $p and $p->{backendNodeId} == $backendNodeId
                    } @foundNodes;
                };

                # Resolve the found nodes directly with the
                # found node ids instead of returning the numbers and fetching
                # them later
                my @nodes = map {
                    # Upgrade the attributes to a hash, ruining their order:
                    my $n = $nodes{ $_ };
                    $self->_fetchNode( 0+$_, $n );
                } @foundNodes;

                Future->wait_all( @nodes );
            });
        } else {
            return Future->done()
        };
    });
}

# If we have the attributes, don't fetch them separately
sub _fetchNode( $self, $nodeId, $attributes = undef ) {
    $self->log('trace', sprintf "Resolving nodeId %s", $nodeId );
    my $s = $self;
    weaken $s;
    my $body = $self->driver->send_message( 'DOM.resolveNode', nodeId => 0+$nodeId );
    if( $attributes ) {
        $attributes = Future->done( $attributes )
    } else {
        $attributes = $self->driver->send_message( 'DOM.getAttributes', nodeId => 0+$nodeId );
    };
    Future->wait_all( $body, $attributes )->then( sub( $body, $attributes ) {
        $body = $body->get->{object};
        my $attr = $attributes->get;
        $attributes = $attr->{attributes};
        my $nodeName = $body->{description};
        $nodeName =~ s!#.*!!;
        my $node = {
            nodeId => $nodeId,
            objectId => $body->{ objectId },
            backendNodeId => $attr->{ backendNodeId },
            attributes => {
                @{ $attributes },
            },
            nodeName => $nodeName,
            driver => $s->driver,
            mech => $s,
            _generation => $s->_generation,
        };
        Future->done( WWW::Mechanize::Chrome::Node->new( $node ));
    })->catch(sub {
        warn "Node $nodeId has gone away in the meantime, could not resolve";
        Future->done( WWW::Mechanize::Chrome::Node->new( {} ) );
    });
}

sub xpath( $self, $query, %options) {
    if ('ARRAY' ne (ref $query||'')) {
        $query = [$query];
    };

    if( not exists $options{ frames }) {
        $options{ frames }= $self->{frames};
    };

    my $single = $options{ single };
    my $first  = $options{ one };
    my $maybe  = $options{ maybe };
    my $any    = $options{ any };
    my $return_first_element = ($single or $first or $maybe or $any );
    $options{ user_info }||= join "|", @$query;

    # Construct some helper variables
    my $zero_allowed = not ($single or $first);
    my $two_allowed  = not( $single or $maybe);

    # Sanity check for the common error of
    # my $item = $mech->xpath("//foo");
    if (! exists $options{ all } and not ($return_first_element)) {
        $self->signal_condition(join "\n",
            "You asked for many elements but seem to only want a single item.",
            "Did you forget to pass the 'single' option with a true value?",
            "Pass 'all => 1' to suppress this message and receive the count of items.",
        ) if defined wantarray and !wantarray;
    };

    my @res;

    if( $options{ document }) {
        warn sprintf "Document %s", $options{ document }->{id};
    };

    my $doc= $options{ document } ? Future->done( $options{ document } ) : $self->document_future;

    $doc->then( sub {
        my $q = join "|", @$query;

        my @found;
        my $id;
        if ($options{ node }) {
            $id = $options{ node }->backendNodeId;
        };
        Future->wait_all(
            map {
                $self->_performSearch( query => $_, backendNodeId => $id )
            } @$query
        );
    })->then( sub {
        my @found = map { my @r = $_->get; @r ? map { $_->get } @r : () } @_;
        push @res, @found;
        Future->done( 1 );
    })->get;

    # Determine if we want only one element
    #     or a list, like WWW::Mechanize::Chrome

    if (! $zero_allowed and @res == 0) {
        $self->signal_condition( sprintf "No elements found for %s", $options{ user_info } );
    };
    if (! $two_allowed and @res > 1) {
        #$self->highlight_node(@res);
        warn $_->get_text() || '<no text>' for @res;
        $self->signal_condition( sprintf "%d elements found for %s", (scalar @res), $options{ user_info } );
    };

    $return_first_element ? $res[0] : @res
}

=head2 C<< $mech->by_id( $id, %options ) >>

  my @text = $mech->by_id('_foo:bar');

Returns all nodes matching the given ids. If
C<$id> is an array reference, it returns
all nodes matched by any of the ids in the array.

This method is equivalent to calling C<< ->xpath >> :

    $self->xpath(qq{//*[\@id="$_"]}, %options)

It is convenient when your element ids get mistaken for
CSS selectors.

=cut

sub by_id {
    my ($self,$query,%options) = @_;
    if ('ARRAY' ne (ref $query||'')) {
        $query = [$query];
    };
    $options{ user_info } ||= "id "
                            . join(" or ", map {qq{'$_'}} @$query)
                            . " found";
    $query = [map { qq{.//*[\@id="$_"]} } @$query];
    $self->xpath($query, %options)
}

=head2 C<< $mech->click( $name [,$x ,$y] ) >>

  $mech->click( 'go' );
  $mech->click({ xpath => '//button[@name="go"]' });

Has the effect of clicking a button (or other element) on the current form. The
first argument is the C<name> of the button to be clicked. The second and third
arguments (optional) allow you to specify the (x,y) coordinates of the click.

If there is only one button on the form, C<< $mech->click() >> with
no arguments simply clicks that one button.

If you pass in a hash reference instead of a name,
the following keys are recognized:

=over 4

=item *

C<text> - Find the element to click by its contained text

=item *

C<selector> - Find the element to click by the CSS selector

=item *

C<xpath> - Find the element to click by the XPath query

=item *

C<dom> - Click on the passed DOM element

You can use this to click on arbitrary page elements. There is no convenient
way to pass x/y co-ordinates with this method.

=item *

C<id> - Click on the element with the given id

This is useful if your document ids contain characters that
do look like CSS selectors. It is equivalent to

    xpath => qq{//*[\@id="$id"]}

=item *

C<intrapage> - Override the detection of whether to wait for a HTTP response
or not. Setting this will never wait for an HTTP response.

=back

Returns a L<HTTP::Response> object.

As a deviation from the WWW::Mechanize API, you can also pass a
hash reference as the first parameter. In it, you can specify
the parameters to search much like for the C<find_link> calls.

=cut

sub click {
    my ($self,$name,$x,$y) = @_;
    my %options;
    my @buttons;

    if (! defined $name) {
        croak("->click called with undef link");
    } elsif (ref $name and blessed $name and $name->isa('WWW::Mechanize::Chrome::Node') ) {
        $options{ dom } = $name;
    } elsif (ref $name eq 'HASH') { # options
        %options = %$name;
    } else {
        $options{ name } = $name;
    };

    if( exists $options{ text }) {
        $options{ xpath } = sprintf q{//*[text() = "%s"]}, quote_xpath( $options{ text });
    };

    if (exists $options{ name }) {
        $name = quotemeta($options{ name }|| '');
        $options{ xpath } = [
                       sprintf( q{//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="button" and @name="%s") or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input" and (@type="button" or @type="submit" or @type="image") and @name="%s")]}, $name, $name),
        ];
        if ($options{ name } eq '') {
            push @{ $options{ xpath }},
                       q{//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" or translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input") and @type="button" or @type="submit" or @type="image"]},
            ;
        };
        $options{ user_info } = "Button with name '$name'";
    };

    if ($options{ dom }) {
        @buttons = $options{ dom };
    } else {
        @buttons = $self->_option_query(%options);
    };

    # Get the node as an object so we can find its position and send the clicks:
    $self->log('trace', sprintf "Resolving nodeId %d to object for clicking", $buttons[0]->nodeId );
    my $id = $buttons[0]->objectId;
    #warn Dumper $self->driver->send_message('Runtime.getProperties', objectId => $id)->get;
    #warn Dumper $self->driver->send_message('Runtime.callFunctionOn', objectId => $id, functionDeclaration => 'function() { this.focus(); }', arguments => [])->get;

    my $response =
    $self->_mightNavigate( sub {
        $self->driver->send_message('Runtime.callFunctionOn', objectId => $id, functionDeclaration => 'function() { this.click(); }', arguments => [])
    }, %options)
    ->get;
}

# Internal method to run either an XPath, CSS or id query against the DOM
# Returns the element(s) found
my %rename = (
    xpath => 'xpath',
    selector => 'selector',
    id => 'by_id',
    by_id => 'by_id',
);

sub _option_query {
    my ($self,%options) = @_;
    my ($method,$q);
    for my $meth (keys %rename) {
        if (exists $options{ $meth }) {
            $q = delete $options{ $meth };
            $method = $rename{ $meth } || $meth;
        }
    };
    _default_limiter( 'one' => \%options );
    croak "Need either a name, a selector or an xpath key!"
        if not $method;
    return $self->$method( $q, %options );
};

# Return the default limiter if no other limiting option is set:
sub _default_limiter {
    my ($default, $options) = @_;
    if (! grep { exists $options->{ $_ } } qw(single one maybe all any)) {
        $options->{ $default } = 1;
    };
    return ()
};

=head2 C<< $mech->click_button( ... ) >>

  $mech->click_button( name => 'go' );
  $mech->click_button( input => $mybutton );

Has the effect of clicking a button on the current form by specifying its
name, value, or index. Its arguments are a list of key/value pairs. Only
one of name, number, input or value must be specified in the keys.

=over 4

=item *

C<name> - name of the button

=item *

C<value> - value of the button

=item *

C<input> - DOM node

=item *

C<id> - id of the button

=item *

C<number> - number of the button

=back

If you find yourself wanting to specify a button through its
C<selector> or C<xpath>, consider using C<< ->click >> instead.

=cut

sub click_button {
    my ($self,%options) = @_;
    my $node;
    my $xpath;
    my $user_message;
    if (exists $options{ input }) {
        $node = delete $options{ input };
    } elsif (exists $options{ name }) {
        my $v = delete $options{ name };
        $xpath = sprintf( '//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" and @name="%s") or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input" and @type="button" or @type="submit" and @name="%s")]', $v, $v);
        $user_message = "Button name '$v' unknown";
    } elsif (exists $options{ value }) {
        my $v = delete $options{ value };
        $xpath = sprintf( '//*[(translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" and @value="%s") or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")="input" and (@type="button" or @type="submit") and @value="%s")]', $v, $v);
        $user_message = "Button value '$v' unknown";
    } elsif (exists $options{ id }) {
        my $v = delete $options{ id };
        $xpath = sprintf '//*[@id="%s"]', $v;
        $user_message = "Button name '$v' unknown";
    } elsif (exists $options{ number }) {
        my $v = delete $options{ number };
        $xpath = sprintf '//*[translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "button" or (translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "input" and @type="submit")][%s]', $v;
        $user_message = "Button number '$v' out of range";
    };
    $node ||= $self->xpath( $xpath,
                          node => $self->current_form,
                          single => 1,
                          user_message => $user_message,
              );
    if ($node) {
        $self->click({ dom => $node, %options });
    } else {

        $self->signal_condition($user_message);
    };

}

=head1 FORM METHODS

=head2 C<< $mech->current_form() >>

  print $mech->current_form->{name};

Returns the current form.

This method is incompatible with L<WWW::Mechanize>.
It returns the DOM C<< <form> >> object and not
a L<HTML::Form> instance.

The current form will be reset by WWW::Mechanize::Chrome
on calls to C<< ->get() >> and C<< ->get_local() >>,
and on calls to C<< ->submit() >> and C<< ->submit_with_fields >>.

=cut

sub current_form {
    my( $self, %options )= @_;
    # Find the first <FORM> element from the currently active element
    $self->form_number(1) unless $self->{current_form};
    $self->{current_form};
}

sub clear_current_form {
    undef $_[0]->{current_form};
};

sub active_form {
    my( $self, %options )= @_;
    # Find the first <FORM> element from the currently active element
    my $focus= $self->driver->get_active_element;

    if( !$focus ) {
        warn "No active element, hence no active form";
        return
    };

    my $form= $self->xpath( './ancestor-or-self::FORM', node => $focus, maybe => 1 );

}

=head2 C<< $mech->dump_forms( [$fh] ) >>

  open my $fh, '>', 'form-log.txt'
      or die "Couldn't open logfile 'form-log.txt': $!";
  $mech->dump_forms( $fh );

Prints a dump of the forms on the current page to
the filehandle C<$fh>. If C<$fh> is not specified or is undef, it dumps
to C<STDOUT>.

=cut

sub dump_forms {
    my $self = shift;
    my $fh = shift || \*STDOUT;

    for my $form ( $self->forms ) {
        print {$fh} "[FORM] ", $form->get_attribute('name') || '<no name>', ' ', $form->get_attribute('action'), "\n";
        #for my $f ($self->xpath( './/*', node => $form )) {
        #for my $f ($self->xpath( './/*[contains(" "+translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")+" "," input textarea button select "
        #                                        )]', node => $form )) {
        for my $f ($self->xpath( './/*[contains(" input textarea button select ",concat(" ",translate(local-name(.), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")," "))]', node => $form )) {
            my $type;
            if($type= $f->get_attribute('type') || '' ) {
                $type= " ($type)";
            };

            print {$fh} "    [", $f->get_attribute('tagName'), $type, "] ", $f->get_attribute('name') || '<no name>', "\n";
        };
    }
    return;
}

=head2 C<< $mech->form_name( $name [, %options] ) >>

  $mech->form_name( 'search' );

Selects the current form by its name. The options
are identical to those accepted by the L<< /$mech->xpath >> method.

=cut

sub form_name {
    my ($self,$name,%options) = @_;
    $name = quote_xpath $name;
    _default_limiter( single => \%options );
    $self->{current_form} = $self->selector("form[name='$name']",
        user_info => "form name '$name'",
        %options
    );
};

=head2 C<< $mech->form_id( $id [, %options] ) >>

  $mech->form_id( 'login' );

Selects the current form by its C<id> attribute.
The options
are identical to those accepted by the L<< /$mech->xpath >> method.

This is equivalent to calling

    $mech->by_id($id,single => 1,%options)

=cut

sub form_id {
    my ($self,$name,%options) = @_;

    _default_limiter( single => \%options );
    $self->{current_form} = $self->by_id($name,
        user_info => "form with id '$name'",
        %options
    );
};

=head2 C<< $mech->form_number( $number [, %options] ) >>

  $mech->form_number( 2 );

Selects the I<number>th form.
The options
are identical to those accepted by the L<< /$mech->xpath >> method.

=cut

sub form_number {
    my ($self,$number,%options) = @_;

    _default_limiter( single => \%options );
    $self->{current_form} = $self->xpath("(//form)[$number]",
        user_info => "form number $number",
        %options
    );

    $self->{current_form};
};

=head2 C<< $mech->form_with_fields( [$options], @fields ) >>

  $mech->form_with_fields(
      'user', 'password'
  );

Find the form which has the listed fields.

If the first argument is a hash reference, it's taken
as options to C<< ->xpath >>.

See also L<< /$mech->submit_form >>.

=cut

sub form_with_fields {
    my ($self,@fields) = @_;
    my $options = {};
    if (ref $fields[0] eq 'HASH') {
        $options = shift @fields;
    };
    my @clauses  = map { $self->element_query([qw[input select textarea]], { 'name' => $_ })} @fields;


    my $q = "//form[" . join( " and ", @clauses)."]";
    #warn $q;
    _default_limiter( single => $options );
    $self->{current_form} = $self->xpath($q,
        user_info => "form with fields [@fields]",
        %$options
    );
    #warn $form;
    $self->{current_form};
};

=head2 C<< $mech->forms( %options ) >>

  my @forms = $mech->forms();

When called in a list context, returns a list
of the forms found in the last fetched page.
In a scalar context, returns a reference to
an array with those forms.

The options
are identical to those accepted by the L<< /$mech->selector >> method.

The returned elements are the DOM C<< <form> >> elements.

=cut

sub forms {
    my ($self, %options) = @_;
    my @res = $self->selector('form', %options);
    return wantarray ? @res
                     : \@res
};

=head2 C<< $mech->field( $selector, $value, [,\@pre_events [,\@post_events]] ) >>

  $mech->field( user => 'joe' );
  $mech->field( not_empty => '', [], [] ); # bypass JS validation

Sets the field with the name given in C<$selector> to the given value.
Returns the value.

The method understands very basic CSS selectors in the value for C<$selector>,
like the L<HTML::Form> find_input() method.

A selector prefixed with '#' must match the id attribute of the input.
A selector prefixed with '.' matches the class attribute. A selector
prefixed with '^' or with no prefix matches the name attribute.

By passing the array reference C<@pre_events>, you can indicate which
Javascript events you want to be triggered before setting the value.
C<@post_events> contains the events you want to be triggered
after setting the value.

By default, the events set in the
constructor for C<pre_events> and C<post_events>
are triggered.

=cut

sub field {
    my ($self,$name,$value,$pre,$post) = @_;
    $self->get_set_value(
        name => $name,
        value => $value,
        pre => $pre,
        post => $post,
        node => $self->current_form,
    );
}

=head2 C<< $mech->sendkeys( %options ) >>

    $mech->sendkeys( string => "Hello World" );

Sends a series of keystrokes. The keystrokes can be either a string or a
reference to an array containing the detailed data as hashes.

=over 4

=item B<string> - the string to send as keystrokes

=item B<keys> - reference of the array to send as keystrokes

=item B<delay> - delay in ms to sleep between keys

=back

=cut

sub sendkeys_future( $self, %options ) {
    $options{ keys } ||= [ map +{ type => 'char', text => $_ },
                           split m//, $options{ string }
                         ];

    my $f = Future->done(1);

    for my $key (@{ $options{ keys }}) {
        $f = $f->then(sub {
            $self->driver->send_message('Input.dispatchKeyEvent', %$key );
        });
        if( defined $options{ delay }) {
            $f->then(sub {
                $self->sleep( $options{ delay });
            });
        };
    };

    return $f
};

sub sendkeys( $self, %options ) {
    $self->sendkeys_future( %options )->get
}

=head2 C<< $mech->upload( $selector, $value ) >>

  $mech->upload( user_picture => 'C:/Users/Joe/face.png' );

Sets the file upload field with the name given in C<$selector> to the given
file. The filename must be an absolute path and filename in the local
filesystem.

The method understands very basic CSS selectors in the value for C<$selector>,
like the C<< ->field >> method.

=cut

sub upload($self,$name,$value) {
    my %options;

    my @fields = $self->_field_by_name(
                     name => $name,
                     user_info => "upload field with name '$name'",
                     %options );
    $value = [$value]
        if ! ref $value;

    # Stringify all files:
    @$value = map { "$_" } @$value;

    if( @fields ) {
        $self->driver->send_message('DOM.setFileInputFiles',
            nodeId => 0+$fields[0]->nodeId,
            files => $value,
            )->get;
    }

}


=head2 C<< $mech->value( $selector_or_element, [%options] ) >>

    print $mech->value( 'user' );

Returns the value of the field given by C<$selector_or_name> or of the
DOM element passed in.

The legacy form of

    $mech->value( name => value );

is also still supported but will likely be deprecated
in favour of the C<< ->field >> method.

For fields that can have multiple values, like a C<select> field,
the method is context sensitive and returns the first selected
value in scalar context and all values in list context.

Note that this method does not support file uploads. See the C<< ->upload >>
method for that.

=cut

sub value {
    if (@_ == 3) {
        my ($self,$name,$value) = @_;
        return $self->field($name => $value);
    } else {
        my ($self,$name,%options) = @_;
        return $self->get_set_value(
            node => $self->current_form,
            %options,
            name => $name,
        );
    };
};

=head2 C<< $mech->get_set_value( %options ) >>

Allows fine-grained access to getting/setting a value
with a different API. Supported keys are:

  name
  value
  pre
  post

in addition to all keys that C<< $mech->xpath >> supports.

=cut

sub _field_by_name {
    my ($self,%options) = @_;
    my @fields;
    my $name  = delete $options{ name };
    my $attr = 'name';
    if ($name =~ s/^\^//) { # if it starts with ^, it's supposed to be a name
        $attr = 'name'
    } elsif ($name =~ s/^#//) {
        $attr = 'id'
    } elsif ($name =~ s/^\.//) {
        $attr = 'class'
    };
    if (blessed $name) {
        @fields = $name;
    } else {
        _default_limiter( single => \%options );
        my $query = $self->element_query([qw[input select textarea]], { $attr => $name });
        @fields = $self->xpath($query,%options);
    };
    @fields
}

sub get_set_value($self,%options) {
    my $set_value = exists $options{ value };
    my $value = delete $options{ value };
    my $pre   = delete $options{pre}  || $self->{pre_value};
    $pre = [$pre]
        if (! ref $pre);
    my $post  = delete $options{post} || $self->{post_value};
    $post = [$post]
        if (! ref $post);
    my $name  = delete $options{ name };

    my @fields = $self->_field_by_name(
                     name => $name,
                     user_info => "input with name '$name'",
                     %options );

    if (my $obj = $fields[0]) {

        my $tag = $obj->get_tag_name();
        if ($set_value) {
            my %method = (
                input    => 'value',
                textarea => 'content',
                select   => 'selected',
            );
            my $method = $method{ lc $tag };

            # Send pre-change events:

            my $id = $obj->{objectId};
            if( 'value' eq $method ) {
                $self->driver->send_message('DOM.setAttributeValue', nodeId => 0+$obj->nodeId, name => 'value', value => "$value" )->get;

            } elsif( 'selected' eq $method ) {
                # ignoring undef; but [] would reset to no option
                if (defined $value) {
                    $value = [ $value ] unless ref $value;
                    $self->driver->send_message(
                        'Runtime.callFunctionOn',
                        objectId => $id,
                        functionDeclaration => <<'JS',
function(newValue) {
  var i, j;
  if (this.multiple == true) {
    for (i=0; i<this.options.length; i++) {
      this.options[i].selected = false
    }
  }
  for (j=0; j<newValue.length; j++) {
    for (i=0; i<this.options.length; i++) {
      if (this.options[i].value == newValue[j]) {
        this.options[i].selected = true
      }
    }
  }
}
JS
                        arguments => [{ value => $value }],
                    )->get;
                }
            } elsif( 'content' eq $method ) {
                $self->driver->send_message('Runtime.callFunctionOn',
                    objectId => $id,
                    functionDeclaration => 'function(newValue) { this.innerHTML = newValue }',
                    arguments => [{ value => $value }]
                )->get;
            } else {
                die "Don't know how to set the value for node '$tag', sorry";
            };

            # Send post-change events
        };

        # Don't bother to fetch the field's value if it's not wanted
        return unless defined wantarray;

        # We could save some work here for the simple case of single-select
        # dropdowns by not enumerating all options
        if ('SELECT' eq uc $tag) {
            my $id = $obj->{objectId};
            my $arr = $self->driver->send_message(
                    'Runtime.callFunctionOn',
                    objectId => $id,
                    functionDeclaration => <<'JS',
function() {
  var i;
  var arr = [];
  for (i=0; i<this.options.length; i++) {
    if (this.options[i].selected == true) {
      arr.push(this.options[i].value);
    }
  }
  return arr;
}
JS
                    arguments => [],
                    returnByValue => JSON::true)->get->{result};

            my @values = @{$arr->{value}};
            if (wantarray) {
                return @values
            } else {
                return $values[0];
            }
        } else {
            # Need to handle SELECT fields here
            return $obj->get_attribute('value');
        };
    } else {
        return
    }
}

=head2 C<< $mech->submit( $form ) >>

  $mech->submit;

Submits the form. Note that this does B<not> fire the C<onClick>
event and thus also does not fire eventual Javascript handlers.
Maybe you want to use C<< $mech->click >> instead.

The default is to submit the current form as returned
by C<< $mech->current_form >>.

=cut

sub submit($self,$dom_form = $self->current_form) {
    if ($dom_form) {
        # We should prepare for navigation here as well
        # The __proto__ invocation is so we can have a HTML form field entry
        # named "submit"
        $self->_mightNavigate( sub {
            $self->driver->send_message(
                'Runtime.callFunctionOn',
                objectId => $dom_form->objectId,
                functionDeclaration => 'function() { var action = this.action; var isCallable = action && typeof(action) === "function"; if( isCallable) { action() } else { this.__proto__.submit.apply(this) }}'
            );
        })
        ->get;

        $self->clear_current_form;
    } else {
        croak "I don't know which form to submit, sorry.";
    }
    return $self->response;
};

=head2 C<< $mech->submit_form( %options ) >>

  $mech->submit_form(
      with_fields => {
          user => 'me',
          pass => 'secret',
      }
  );

This method lets you select a form from the previously fetched page,
fill in its fields, and submit it. It combines the form_number/form_name,
C<< ->set_fields >> and C<< ->click methods >> into one higher level call. Its
arguments are a list of key/value pairs, all of which are optional.

=over 4

=item *

C<< form => $mech->current_form() >>

Specifies the form to be filled and submitted. Defaults to the current form.

=item *

C<< fields => \%fields >>

Specifies the fields to be filled in the current form

=item *

C<< with_fields => \%fields >>

Probably all you need for the common case. It combines a smart form selector
and data setting in one operation. It selects the first form that contains
all fields mentioned in \%fields. This is nice because you don't need to
know the name or number of the form to do this.

(calls L<< /$mech->form_with_fields() >> and L<< /$mech->set_fields() >>).

If you choose this, the form_number, form_name, form_id and fields options
will be ignored.

=back

=cut

sub submit_form($self,%options) {;

    my $form = delete $options{ form };
    my $fields;
    if (! $form) {
        if ($fields = delete $options{ with_fields }) {
            my @names = keys %$fields;
            $form = $self->form_with_fields( \%options, @names );
            if (! $form) {
                $self->signal_condition("Couldn't find a matching form for @names.");
                return
            };
        } else {
            $fields = delete $options{ fields } || {};
            $form = $self->current_form;
        };
    };

    if (! $form) {
        $self->signal_condition("No form found to submit.");
        return
    };
    $self->do_set_fields( form => $form, fields => $fields );

    my $response;
    if ( $options{button} ) {
        $response = $self->click( $options{button}, $options{x} || 0, $options{y} || 0 );
    }
    else {
        $response = $self->submit();
    }
    return $response;

}

=head2 C<< $mech->set_fields( $name => $value, ... ) >>

  $mech->set_fields(
      user => 'me',
      pass => 'secret',
  );

This method sets multiple fields of the current form. It takes a list of
field name and value pairs. If there is more than one field with the same
name, the first one found is set. If you want to select which of the
duplicate field to set, use a value which is an anonymous array which
has the field value and its number as the 2 elements.

=cut

sub set_fields($self, %fields) {;
    my $f = $self->current_form;
    if (! $f) {
        croak "Can't set fields: No current form set.";
    };
    $self->do_set_fields(form => $f, fields => \%fields);
};

sub do_set_fields {
    my ($self, %options) = @_;
    my $form = delete $options{ form };
    my $fields = delete $options{ fields };

    while (my($n,$v) = each %$fields) {
        if (ref $v) {
            ($v,my $num) = @$v;
            warn "Index larger than 1 not supported, ignoring"
                unless $num == 1;
        };

        $self->get_set_value( node => $form, name => $n, value => $v, %options );
    }
};

=head1 CONTENT MONITORING METHODS

=head2 C<< $mech->is_visible( $element ) >>

=head2 C<< $mech->is_visible(  %options ) >>

  if ($mech->is_visible( selector => '#login' )) {
      print "You can log in now.";
  };

Returns true if the element is visible, that is, it is
a member of the DOM and neither it nor its ancestors have
a CSS C<visibility> attribute of C<hidden> or
a C<display> attribute of C<none>.

You can either pass in a DOM element or a set of key/value
pairs to search the document for the element you want.

=over 4

=item *

C<xpath> - the XPath query

=item *

C<selector> - the CSS selector

=item *

C<dom> - a DOM node

=back

The remaining options are passed through to either the
L<< /$mech->xpath|xpath >> or L<< /$mech->selector|selector >> method.

=cut

sub is_visible ( $self, @ ) {
    my %options;
    if (2 == @_) {
        ($self,$options{dom}) = @_;
    } else {
        ($self,%options) = @_;
    };
    _default_limiter( 'maybe', \%options );
    if (! $options{dom}) {
        $options{dom} = $self->_option_query(%options);
    };
    # No element means not visible
    return
        unless $options{ dom };
    #$options{ window } ||= $self->tab->{linkedBrowser}->{contentWindow};

    my $id = $options{ dom }->objectId;
    my ($val, $type) = $self->callFunctionOn(<<'JS', objectId => $id, arguments => []); #->get;
    function ()
    {
        var obj = this;
        while (obj) {
            // No object
            if (!obj) return false;

            try {
                if( obj["parentNode"] ) 1;
            } catch (e) {
                // Dead object
                return false
            };
            // Descends from document, so we're done
            if (obj.parentNode === obj.ownerDocument) {
                return true;
            };
            // Not in the DOM
            if (!obj.parentNode) {
                return false;
            };
            // Direct style check
            if (obj.style) {
                if (obj.style.display == 'none') return false;
                if (obj.style.visibility == 'hidden') return false;
            };

            if (window.getComputedStyle) {
                var style = window.getComputedStyle(obj, null);
                if (style.display == 'none') {
                    return false; }
                if (style.visibility == 'hidden') {
                    return false;
                };
            };
            obj = obj.parentNode;
        };
        // The object does not live in the DOM at all
        return false
    }
JS
    $type eq 'boolean'
        or die "Don't know how to handle Javascript type '$type'";
    return $val
};

=head2 C<< $mech->wait_until_invisible( $element ) >>

=head2 C<< $mech->wait_until_invisible( %options ) >>

  $mech->wait_until_invisible( $please_wait );

Waits until an element is not visible anymore.

Takes the same options as L<< $mech->is_visible/->is_visible >>.

In addition, the following options are accepted:

=over 4

=item *

C<timeout> - the timeout after which the function will C<croak>. To catch
the condition and handle it in your calling program, use an L<eval> block.
A timeout of C<0> means to never time out.

=item *

C<sleep> - the interval in seconds used to L<sleep>. Subsecond
intervals are possible.

=back

Note that when passing in a selector, that selector is requeried
on every poll instance. So the following query will work as expected:

  xpath => '//*[contains(text(),"stand by")]'

This also means that if your selector query relies on finding
a changing text, you need to pass the node explicitly instead of
passing the selector.

=cut

sub wait_until_invisible( $self, %options ) {
    if (2 == @_) {
        ($self,$options{dom}) = @_;
    } else {
        ($self,%options) = @_;
    };
    my $sleep = delete $options{ sleep } || 0.3;
    my $timeout = delete $options{ timeout } || 0;

    _default_limiter( 'maybe', \%options );

    my $timeout_after;
    if ($timeout) {
        $timeout_after = time + $timeout;
    };
    my $v;
    my $node;
    do {
        $node = $options{ dom };
        if (! $node) {
            $node = $self->_option_query(%options);
        };
        return
            unless $node;
        $self->sleep( $sleep );

        # If $node goes away due to a page reload, ->is_visible could die:
        $v = eval { $self->is_visible($node) };
    } while ( $v
           and (!$timeout or time < $timeout_after ));
    if ($v and $timeout and time >= $timeout_after) {
        croak "Timeout of $timeout seconds reached while waiting for element to become invisible";
    };
};

=head2 C<< $mech->wait_until_visible( %options ) >>

  $mech->wait_until_visible( selector => 'a.download' );

Waits until an query returns a visible element.

Takes the same options as L<< $mech->is_visible/->is_visible >>.

In addition, the following options are accepted:

=over 4

=item *

C<timeout> - the timeout after which the function will C<croak>. To catch
the condition and handle it in your calling program, use an L<eval> block.
A timeout of C<0> means to never time out.

=item *

C<sleep> - the interval in seconds used to L<sleep>. Subsecond
intervals are possible.

=back

Note that when passing in a selector, that selector is requeried
on every poll instance. So the following query will work as expected:

=cut

sub wait_until_visible( $self, %options ) {
    my $sleep = delete $options{ sleep } || 0.3;
    my $timeout = delete $options{ timeout } || 0;

    _default_limiter( 'any', \%options );

    my $timeout_after;
    if ($timeout) {
        $timeout_after = time + $timeout;
    };
    do {
        # If $node goes away due to a page reload, ->is_visible could die:
        my @nodes =
            grep { eval { $self->is_visible( dom => $_ ) } }
            $self->_option_query(%options);

        if( @nodes ) {
            return @nodes
        };
        $self->sleep( $sleep );
    } while (!$timeout_after or time < $timeout_after );
    if (time >= $timeout_after) {
        croak "Timeout of $timeout seconds reached while waiting for element to become invisible";
    };
};

=head1 CONTENT RENDERING METHODS

=head2 C<< $mech->content_as_png() >>

    my $png_data = $mech->content_as_png();

    # Create scaled-down 480px wide preview
    my $png_data = $mech->content_as_png(undef, { width => 480 });

Returns the given tab or the current page rendered as PNG image.

All parameters are optional.

=over 4

=back

This method is specific to WWW::Mechanize::Chrome.

=cut

sub _as_raw_png( $self, $image ) {
    my $data;
    $image->write( data => \$data, type => 'png' );
    $data
}

sub _content_as_png($self, $rect={}, $target={} ) {
    $self->driver->send_message('Page.captureScreenshot', format => 'png' )->then( sub( $res ) {
        require Imager;
        my $img = Imager->new ( data => decode_base64( $res->{data} ), format => 'png' );
        # Cut out the wanted part
        if( scalar keys %$rect) {
            $img = $img->crop( %$rect );
        };
        # Resize image to width/height
        if( scalar keys %$target) {
            my %args;
            $args{ ypixels } = $target->{ height }
                if $target->{height};
            $args{ xpixels } = $target->{ width }
                if $target->{width};
            $args{ scalefactor } = $target->{ scalex } || $target->{scaley};
            $img = $img->scale( %args );
        };
        return Future->done( $img )
    });
};


sub content_as_png($self, $rect={}, $target={}) {
    my $img = $self->_content_as_png( $rect, $target )->get;
    return $self->_as_raw_png( $img );
};

sub getResourceTree_future( $self ) {
    $self->driver->send_message( 'Page.getResourceTree' )
    ->then( sub( $result ) {
        Future->done( $result->{frameTree} )
    })
}

sub getResourceContent_future( $self, $url_or_resource, $frameId=$self->frameId, %additional ) {
    my $url = ref $url_or_resource ? $url_or_resource->{url} : $url_or_resource;
    %additional = (%$url_or_resource,%additional) if ref $url_or_resource;
    $self->driver->send_message( 'Page.getResourceContent', frameId => $frameId, url => $url )
    ->then( sub( $result ) {
        if( delete $result->{base64Encoded}) {
            $result->{content} = decode_base64( $result->{content} )
        }
        %$result = (%additional, %$result);
        Future->done( $result )
    })
}

# Replace that later with MIME::Detect
our %extensions = (
    'image/jpeg' => '.jpg',
    'image/png'  => '.png',
    'image/gif'  => '.gif',
    'text/html'  => '.html',
    'text/plain'  => '.txt',
    'text/stylesheet'  => '.css',
);

# Allow the options to specify whether to filter duplicates here
sub fetchResources_future( $self, %options ) {
    $options{ save } ||= undef;
    $options{ seen } ||= {};
    $options{ names } ||= {};
    my $seen = $options{ seen };
    my $names = $options{ names };
    my $save = $options{ save };

    my $s = $self;
    weaken $s;

    $self->getResourceTree_future
    ->then( sub( $tree ) {
        my @requested;
        # Also fetch the frame itself?!
        # Or better reuse ->content?!
        # $tree->{frame}

        # build the map from URLs to file names
        # This should become a separate method
        # Also something like get_page_resources, that returns the linear
        # list of resources for all frames etc.
        for my $res ($tree->{frame}, @{ $tree->{resources}}) {
            # Also include childFrames and subresources here, recursively

            if( $names->{ $res->{url} } ) {
                #warn "Skipping $res->{url} (already saved)";
                next;
            };

            # we will only scrape HTTP resources
            next if $res->{url} !~ /^https?:/i;
            warn $res->{url};
            my $target = $s->filenameFromUrl( $res->{url}, $extensions{ $res->{mimeType} });
            my %filenames = reverse %$names;

            my $duplicates;
            my $old_target = $target;
            while( $filenames{ $target }) {
                $duplicates++;
                ( $target = $old_target )=~ s!\.(\w+)$!_$duplicates.$1!;
            };
            $names->{ $res->{url} } = $target;
        };

        # retrieve and save the resource content for each resource
        for my $res ($tree->{frame}, @{ $tree->{resources}}) {
            next if $seen->{ $res->{url} };

            # we will only scrape HTTP resources
            next if $res->{url} !~ /^https?:/i;
            my $fetch = $s->getResourceContent_future( $res );
            if( $save ) {
                warn "Will save $res->{url}";
                $fetch = $fetch->then( $save );
            };
            push @requested, $fetch;
        };
        return Future->wait_all( @requested )->catch(sub {
            warn $@;
        });
    })->catch(sub {
        warn $@;
    });
}

=head2 C<< $mech->saveResources_future >>

    my $file_map = $mech->saveResources_future(
        target_file => 'this_page.html',
        target_dir  => 'this_page_files/',
    )->get();

Rough prototype of "Save Complete Page" feature

=cut

sub saveResources_future( $self, %options ) {
    my $target_file = $options{ target_file }
        or croak "Need filename to save as ('target_file')";
    my $target_dir = $options{ target_dir };
    if( ! defined $target_dir ) {
        ($target_dir = $target_file) =~ s!\.\w+$! files!i;
    };
    if( not -e $target_dir ) {
        mkdir $target_dir
            or croak "Couldn't create '$target_dir': $!";
    }

    my %names = (
        $self->uri => $target_file,
    );
    my $s = $self;
    weaken $s;
    $self->fetchResources_future( save => sub( $resource ) {

        # For mime/html targets without a name, use the title?!
        # Rewrite all HTML, CSS links

        # We want to store the top HTML under the name passed in (!)
        $names{ $resource->{url} } ||= File::Spec->catfile( $target_dir, $names{ $resource->{url} });
        my $target = $names{ $resource->{url} }
            or die "Don't have a filename for URL '$resource->{url}' ?!";
        $s->log( 'debug', "Saving '$resource->{url}' to '$target'" );
        open my $fh, '>', $target
            or croak "Couldn't save url '$resource->{url}' to $target: $!";
        binmode $fh;
        print $fh $resource->{content};
        close $fh;

        Future->done( $resource );
    }, names => \%names, seen => \my %seen )->then( sub( @resources ) {
        Future->done( %names );
    })->catch(sub {
        warn $@;
    });
}

sub filenameFromUrl( $self, $url, $extension ) {
    my $target = $url;
    $target =~ s![\&\?\<\>\{\}\|\:\*]!_!g;
    $target =~ s!.*[/\\]!!;

    # Add/change extension here

    return $target
}

=head2 C<< $mech->viewport_size >>

  print Dumper $mech->viewport_size;
  $mech->viewport_size({ width => 1388, height => 792 });

Returns (or sets) the new size of the viewport (the "window").

The recognized keys are:

  width
  height
  deviceScaleFactor
  mobile
  screenWidth
  screenHeight
  positionX
  positionY

=cut

sub viewport_size_future( $self, $new={} ) {
    my $params = dclone $new;
    if( keys %$params) {
        my %reset = (
            mobile => JSON::false,
            width  => 0,
            height => 0,
            deviceScaleFactor => 0,
            scale  => 1,
            screenWidth => 0,
            screenHeight => 0,
            positionX => 0,
            positionY => 0,
            dontSetVisibleSize => JSON::false,
            screenOrientation => {
                type => 'landscapePrimary',
                angle => 0,
            },
            #viewport => {
            #    'x' => 0,
            #    'y' => 0,
            #    width => 0,
            #    height => 0,
            #    scale  => 1,
            #}
        );
        for my $field (qw( mobile width height deviceScaleFactor )) {
            if( ! exists $params->{ $field }) {
                $params->{$field} = $reset{ $field };
            };
        };
        return $self->driver->send_message('Emulation.setDeviceMetricsOverride', %$params );
    } else {
        return $self->driver->send_message('Emulation.clearDeviceMetricsOverride' );
    };
};

sub viewport_size( $self, $new={} ) {
    $self->viewport_size_future($new)->get
};

=head2 C<< $mech->element_as_png( $element ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my $i_want_this = $mech->element_as_png($shiny);

Returns PNG image data for a single element

=cut

sub element_as_png {
    my ($self, $element) = @_;

    $self->render_element( element => $element, format => 'png' )
};

=head2 C<< $mech->render_element( %options ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my $i_want_this= $mech->render_element(
        element => $shiny,
        format => 'png',
    );

Returns the data for a single element
or writes it to a file. It accepts
all options of C<< ->render_content >>.

Note that while the image will have the node in the upper left
corner, the width and height of the resulting image will still
be the size of the browser window. Cut the image using
C<< element_coordinates >> if you need exactly the element.

=cut

sub render_element {
    my ($self, %options) = @_;
    my $element= delete $options{ element }
        or croak "No element given to render.";

    my $cliprect = $self->element_coordinates( $element );
    my $res = Future->wait_all(
        #$self->driver->send_message('Emulation.setVisibleSize', width => int $cliprect->{width}, height => int $cliprect->{height} ),
        $self->driver->send_message(
            'Emulation.forceViewport',
            'y' => int $cliprect->{top},
            'x' => int $cliprect->{left},
            scale => 1.0
        ),
    )->then(sub {
        $self->_content_as_png()->then( sub( $img ) {
            my $element = $img->crop(
                left => 0,
                top => 0,
                width => $cliprect->{width},
                height => $cliprect->{height});
            Future->done( $self->_as_raw_png( $element ));
        })
    })->get;

    Future->wait_all(
        #$self->driver->send_message('Emulation.setVisibleSize', width => $cliprect->{width}, height => $cliprect->{height} ),
        $self->driver->send_message('Emulation.resetViewport'),
    )->get;

    $res
};

=head2 C<< $mech->element_coordinates( $element ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my ($pos) = $mech->element_coordinates($shiny);
    print $pos->{left},',', $pos->{top};

Returns the page-coordinates of the C<$element>
in pixels as a hash with four entries, C<left>, C<top>, C<width> and C<height>.

This function might get moved into another module more geared
towards rendering HTML.

=cut

sub element_coordinates {
    my ($self, $element) = @_;
    my $cliprect = $self->driver->send_message('Runtime.callFunctionOn', objectId => $element->objectId, functionDeclaration => <<'JS', arguments => [], returnByValue => JSON::true)->get->{result}->{value};
    function() {
        var r = this.getBoundingClientRect();
        return {
            top : r.top
          , left: r.left
          , width: r.width
          , height: r.height
        }
    }
JS
};

=head2 C<< $mech->render_content(%options) >>

    my $pdf_data = $mech->render_content( format => 'pdf' );

Returns the current page rendered as PDF or PNG
as a bytestring.

Note that the PDF format will only be successful with headless Chrome. At least
on Windows, when launching Chrome with a UI, printing to PDF will
be unavailable.

This method is specific to WWW::Mechanize::Chrome.

=cut

sub render_content( $self, %options ) {
    $options{ format } ||= 'png';

    my $fmt = delete $options{ format };
    my $filename = delete $options{ filename };

    my $payload;
    if( $fmt eq 'png' ) {
        $payload = $self->content_as_png( %options )
    } elsif( $fmt eq 'pdf' ) {
        $payload = $self->content_as_pdf( %options );
    };

    if( defined $filename ) {
        open my $fh, '>:raw', $filename
            or croak "Couldn't create '$filename': $!";
        print {$fh} $payload;
    };

    $payload
}

=head2 C<< $mech->content_as_pdf(%options) >>

    my $pdf_data = $mech->content_as_pdf();

    my $pdf_data = $mech->content_as_pdf( format => 'A4' );

    my $pdf_data = $mech->content_as_pdf( paperWidth => 8, paperHeight => 11 );

Returns the current page rendered in PDF format as a bytestring. The page format
can be specified through the C<format> option.

Note that this method will only be successful with headless Chrome. At least on
Windows, when launching Chrome with a UI, printing to PDF will be unavailable.

This method is specific to WWW::Mechanize::Chrome.

=cut

our %PaperFormats = (
    letter  =>  {width =>  8.5,  height =>  11   },
    legal   =>  {width =>  8.5,  height =>  14   },
    tabloid =>  {width =>  11,   height =>  17   },
    ledger  =>  {width =>  17,   height =>  11   },
    a0      =>  {width =>  33.1, height =>  46.8 },
    a1      =>  {width =>  23.4, height =>  33.1 },
    a2      =>  {width =>  16.5, height =>  23.4 },
    a3      =>  {width =>  11.7, height =>  16.5 },
    a4      =>  {width =>  8.27, height =>  11.7 },
    a5      =>  {width =>  5.83, height =>  8.27 },
    a6      =>  {width =>  4.13, height =>  5.83 },
);

sub content_as_pdf($self, %options) {
    if( my $format = delete $options{ format }) {
        my $wh = $PaperFormats{ lc $format }
            or croak "Unknown paper format '$format'";
        @options{'paperWidth','paperHeight'} = @{$wh}{'width','height'};
    };

    my $base64 = $self->driver->send_message('Page.printToPDF', %options)->get->{data};
    my $payload = decode_base64( $base64 );
    if( my $filename = delete $options{ filename } ) {
        open my $fh, '>:raw', $filename
            or croak "Couldn't create '$filename': $!";
        print {$fh} $payload;
    };
    return $payload;
};

=head1 INTERNAL METHODS

These are methods that are available but exist mostly as internal
helper methods. Use of these is discouraged.

=head2 C<< $mech->element_query( \@elements, \%attributes ) >>

    my $query = $mech->element_query(['input', 'select', 'textarea'],
                               { name => 'foo' });

Returns the XPath query that searches for all elements with C<tagName>s
in C<@elements> having the attributes C<%attributes>. The C<@elements>
will form an C<or> condition, while the attributes will form an C<and>
condition.

=cut

sub element_query {
    my ($self, $elements, $attributes) = @_;
        my $query =
            './/*[(' .
                join( ' or ',
                    map {
                        sprintf qq{local-name(.)="%s"}, lc $_
                    } @$elements
                )
            . ') and '
            . join( " and ",
                map { sprintf q{@%s="%s"}, $_, $attributes->{$_} }
                  sort keys(%$attributes)
            )
            . ']';
};

sub post_process
{
    my $self = shift;
    if ( $self->{report_js_errors} ) {
        if ( my @errors = $self->js_errors ) {
            $self->report_js_errors(@errors);
            $self->clear_js_errors;
        }
    }
}

sub report_js_errors
{
    my ( $self, @errors ) = @_;
    @errors = map {
        $_->{message} .
    ( @{$_->{trace}} ? " at $_->{trace}->[-1]->{file} line $_->{trace}->[-1]->{line}" : '') .
    ( @{$_->{trace}} && $_->{trace}->[-1]->{function} ? " in function $_->{trace}->[-1]->{function}" : '')
    } @errors;
    Carp::carp("javascript error: @errors") if @errors;
}

=head1 DEBUGGING METHODS

This module can collect the screencasts that Chrome can produce. The screencasts
are sent to your callback which either feeds them to C<ffmpeg> to create a video
out of them or dumps them to disk as sequential images.

  sub saveFrame {
      my( $mech, $framePNG ) = @_;
      print $framePNG->{data};

  }

  $mech->setScreenFrameCallback( \&saveFrame );
  ... do stuff ...
  $mech->setScreenFrameCallback( undef ); # stop recording

If you want a premade screencast receiver for debugging headless Chrome
sessions, see L<Mojolicious::Plugin::PNGCast>.

=cut

sub _handleScreencastFrame( $self, $frame ) {
    # Meh, this one doesn't get a response I guess. So, not ->send_message, just
    # send a JSON packet to acknowledge the frame
    my $ack;
    my $s = $self;
    weaken $s;
    $ack = $self->driver->send_message(
        'Page.screencastFrameAck',
        sessionId => 0+$frame->{params}->{sessionId} )->then(sub {
            $s->log('trace', 'Screencast frame acknowledged');
            $frame->{params}->{data} = decode_base64( $frame->{params}->{data} );
            $s->{ screenFrameCallback }->( $s, $frame->{params} );
            # forget ourselves
            undef $ack;
    });
}

sub setScreenFrameCallback( $self, $callback=undef, %options ) {
    $self->{ screenFrameCallback } = $callback;

    $options{ format } ||= 'png';
    $options{ everyNthFrame } ||= 1;

    my $action;
    my $s = $self;
    weaken $s;
    if( $callback ) {
        $self->{ screenFrameCallbackCollector } = sub( $frame ) {
            $s->_handleScreencastFrame( $frame );
        };
        $self->{ screenCastFrameListener } =
            $self->add_listener('Page.screencastFrame', $self->{ screenFrameCallbackCollector });
        $action = $s->driver->send_message(
            'Page.startScreencast',
            format => $options{ format },
            everyNthFrame => 0+$options{ everyNthFrame }
        );
    } else {
        $action = $self->driver->send_message('Page.stopScreencast')->then( sub {
            # well, actually, we should only reset this after we're sure that
            # the last frame has been processed. Maybe we should send ourselves
            # a fake event for that, or maybe Chrome tells us
            delete $s->{ screenCastFrameListener };
            Future->done(1);
        });
    }
    $action->get
}

=head2 C<< $mech->sleep >>

  $mech->sleep( 2 ); # wait for things to settle down

Suspends the progress of the program while still handling messages from
Chrome.

The main use of this method is to give Chrome enough time to send all its
screencast frames and to catch up before shutting down the connection.

=cut

sub sleep_future( $self, $seconds ) {
    $self->driver->sleep( $seconds );
}

sub sleep( $self, $seconds ) {
    $self->sleep_future( $seconds )->get;
}

1;

=head1 INCOMPATIBILITIES WITH WWW::Mechanize

As this module is in a very early stage of development,
there are many incompatibilities. The main thing is
that only the most needed WWW::Mechanize methods
have been implemented by me so far.

=head2 Unsupported Methods

At least the following methods are unsupported:

=over 4

=item *

C<< ->find_all_inputs >>

This function is likely best implemented through C<< $mech->selector >>.

=item *

C<< ->find_all_submits >>

This function is likely best implemented through C<< $mech->selector >>.

=item *

C<< ->images >>

This function is likely best implemented through C<< $mech->selector >>.

=item *

C<< ->find_image >>

This function is likely best implemented through C<< $mech->selector >>.

=item *

C<< ->find_all_images >>

This function is likely best implemented through C<< $mech->selector >>.

=back

=head2 Functions that will likely never be implemented

These functions are unlikely to be implemented because
they make little sense in the context of Chrome.

=over 4

=item *

C<< ->clone >>

=item *

C<< ->credentials( $username, $password ) >>

=item *

C<< ->get_basic_credentials( $realm, $uri, $isproxy ) >>

=item *

C<< ->clear_credentials() >>

=item *

C<< ->put >>

I have no use for it

=item *

C<< ->post >>

This module does not yet support POST requests

=back

=head1 INSTALLING

See L<WWW::Mechanize::Chrome::Install>

=head1 SEE ALSO

=over 4

=item *

L<https://developer.chrome.com/devtools/docs/debugging-clients> - the Chrome
DevTools homepage

=item *

L<https://github.com/GoogleChrome/lighthouse> - Google Lighthouse, the main
client of the Chrome API

=item *

L<WWW::Mechanize> - the module whose API grandfathered this module

=item *

L<WWW::Mechanize::Chrome::Node> - objects representing HTML in Chrome

=item *

L<WWW::Mechanize::Firefox> - a similar module with a visible application
automating Firefox

=item *

L<WWW::Mechanize::PhantomJS> - a similar module without a visible application
automating PhantomJS

=back

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 TALKS

I've given a German talk at GPW 2017, see L<http://act.yapc.eu/gpw2017/talk/7027>
and L<https://corion.net/talks> for the slides.

At The Perl Conference 2017 in Amsterdam, I also presented a talk, see
L<http://act.perlconference.org/tpc-2017-amsterdam/talk/7022>.
The slides for the English presentation at TPCiA 2017 are at
L<https://corion.net/talks/WWW-Mechanize-Chrome/www-mechanize-chrome.en.html>.

At the London Perl Workshop 2017 in London, I also presented a talk, see
L<Youtube|https://www.youtube.com/watch?v=V3WeO-iVkAc> . The slides for
that talk are
L<here|https://corion.net/talks/WWW-Mechanize-Chrome/www-mechanize-chrome.en.html>.

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=WWW-Mechanize-Chrome>
or via mail to L<www-mechanize-Chrome-Bugs@rt.cpan.org|mailto:www-mechanize-Chrome-Bugs@rt.cpan.org>.

=head1 CONTRIBUTING

Please see L<WWW::Mechanize::Chrome::Contributing>.

=head1 KNOWN ISSUES

Please see L<WWW::Mechanize::Chrome::Troubleshooting>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 CONTRIBUTORS

Andreas König C<andk@cpan.org>
Tobias Leich C<froggs@cpan.org>
Steven Dondley C<s@dondley.org>

=head1 COPYRIGHT (c)

Copyright 2010-2018 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
