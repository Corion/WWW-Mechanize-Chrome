package WWW::Mechanize::Edge;
use Carp qw(croak);
use Moo;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

extends 'WWW::Mechanize::Chrome';

our $VERSION = '0.22';
our @CARP_NOT;

=head1 NAME

WWW::Mechanize::Edge - control the Microsoft Edge browser

=head1 SYNOPSIS

    my $mech = WWW::Mechanize::Edge->new(
    );

    $mech->get('https://example.com');

=head1 DESCRIPTION

This module allows to launch and control the Microsoft Edge browser through the
Chrome Debugger Protocol. Unfortunately, most of the interesting API is not
implemented by Edge, so only navigating to a page works. Neither retrieving the
page content nor listening for frame events works.

Consider this module as a proof of concept.

=cut

# c:\Users\Corion\AppData\Local\Microsoft\WindowsApps\MicrosoftEdge.exe
# Returns additional directories where the default executable can be found
# on this OS
sub additional_executable_search_directories( $class, $os_style=$^O ) {
    my @search;
    if( $os_style =~ /MSWin/i ) {
        push @search,
            map { "$_\\Microsoft\\WindowsApps" }
            grep {defined}
            ($ENV{'LOCALAPPDATA'},
            );
    }
    @search
}

sub default_executable_names( $class, @other ) {
    my @program_names
        = grep { defined($_) } (
        $ENV{EDGE_BIN},
        @other,
    );
    if( ! @program_names ) {
        push @program_names,
          $^O =~ /mswin/i ? 'MicrosoftEdge.exe'
        : ()
    };
    @program_names
}

sub build_command_line( $class, $options ) {
    my @program_names = $class->default_executable_names( $options->{launch_exe} );
    warn "[[@program_names]]";
    my( $program, $error) = $class->find_executable(\@program_names);
    croak $error if ! $program;

    $options->{port} ||= 9222
      if ! exists $options->{port};

    push @{ $options->{ launch_arg }}, '--devtools-server-port', $options->{ port };

   $options->{ launch_arg } ||= [];
    # We will need a magic cookie so we find the tab that pops up
    $options->{ start_url } ||= "about:blank";

    push @{ $options->{ launch_arg }}, "$options->{start_url}"
        if exists $options->{start_url};
    my @cmd=( $program, @{ $options->{launch_arg}} );

    @cmd
};

sub _setup_driver_future( $self, %options ) {
    $self->driver->connect(
        #new_tab => !$options{ reuse },
        tab     => qr/^about:blank$/i,
    )->catch( sub(@args) {
        my $err = $args[0];
        if( ref $args[1] eq 'HASH') {
            $err .= $args[1]->{Reason};
        };
        Future->fail( $err );
    })
}

sub _waitForNavigationEnd( $self, %options ) {
    # Capture all events as we seem to have initiated some network transfers
    # If we see a Page.frameScheduledNavigation then Chrome started navigating
    # to a new page in response to our click and we should wait until we
    # received all the navigation events.

    #my $frameId = $options{ frameId } || $self->frameId;
    #my $requestId = $options{ requestId } || $self->requestId;
    my $msg = "Capturing events until 'Runtime.executionContextsCleared'";

    $self->log('debug', $msg);
    my $events_f = $self->_collectEvents( sub( $ev ) {
        # Let's assume that the first frame id we see is "our" frame
        my $internal_navigation = (undef);
        my $stopped = (  1 # $options{ just_request }
                       && $ev->{method} eq 'Runtime.executionContextsCleared', # this should be the only one we need (!)
                       # but we never learn which page (!). So this does not play well with iframes :(
        );
        my $domcontent = (  1 # $options{ just_request }
                       && $ev->{method} eq 'Page.domContentEventFired', # this should be the only one we need (!)
                       # but we never learn which page (!). So this does not play well with iframes :(
        );

        my $failed  = 0;
        my $download= 0;
        return $stopped || $internal_navigation || $failed || $download # || $domcontent;
    });

    $events_f;
}

sub _mightNavigate( $self, $get_navigation_future, %options ) {
    undef $self->{frameId};
    undef $self->{requestId};
    my $frameId = $options{ frameId };
    my $requestId = $options{ requestId };

    my $scheduled = Future->done(1);
    my $navigated;
    my $does_navigation;
    my $target_url = $options{ url };

    {
    my $s = $self;
    weaken $s;
    $does_navigation = #$scheduled
        #->then(sub( $ev ) {
        #$self->driver->future->then(sub {
            #my $res;

                  #$s->log('trace', "Navigation started, logging ($ev->{method})");
                  #$s->log('trace', "Navigation started, logging");
                  $navigated++;

                  #$frameId ||= $s->_fetchFrameId( $ev );
                  #$requestId ||= $s->_fetchRequestId( $ev );
                  #$s->{ frameId } = $frameId;
                  #$s->{ requestId } = $requestId;

                  $does_navigation = $s->_waitForNavigationEnd( %options );

            #return $res
            #$res
        #});
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

sub decoded_content_future( $self ) {
    # Join _all_ child nodes together to also fetch DOCTYPE nodes
    # and the stuff that comes after them
    $self->eval_in_page_future(<<'JS' )
        (function(d){
            var e = d.createElement("div");
            e.appendChild(d.documentElement.cloneNode(true));
            return [e.innerHTML,d.inputEncoding];
        })(window.document)
JS
    ->then(sub($value, $type) {
        my( $content,$encoding) = ($value->[0],$value->[1]);
        if (! utf8::is_utf8($content)) {
            # Switch on UTF-8 flag
            # This should never happen, as JSON::XS (and JSON) should always
            # already return proper UTF-8
            # But it does happen.
            $content = Encode::decode($encoding, $content);
        };
        Future->done($content)
    })
}

sub httpMessageFromEvents( $self, $frameId, $events, $url ) {
    HTTP::Response->new(
        200,
        'OK',
    );
};

sub decoded_content($self) {
    $self->decoded_content_future->get;
};

=head2 C<< $mech->uri() >>

    print "We are at " . $mech->uri;

Returns the current document URI.

=cut

sub uri_future( $self ) {
    $self->eval_in_page_future( <<'JS' )
        window.location.href
JS
    ->then( sub($result, $type,@debug) {
        Future->done( URI->new( $result ))
    });
}

sub uri( $self ) {
    $self->uri_future->get()
}

1;

=head1 SEE ALSO

L<https://docs.microsoft.com/en-us/microsoft-edge/devtools-protocol/|Microsoft Edge DevTools Protocol>

=cut