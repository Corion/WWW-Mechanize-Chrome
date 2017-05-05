package WWW::Mechanize::Chrome;
use strict;
use WWW::Mechanize::Plugin::Selector;
use HTTP::Response;
use HTTP::Headers;
use Scalar::Util qw( blessed );
use File::Basename;
use Carp qw(croak carp);
use WWW::Mechanize::Link;
use IO::Socket::INET;

use vars qw($VERSION %link_spec @CARP_NOT);
$VERSION= '0.01';

=head1 NAME

WWW::Mechanize::Chrome - automate the Chrome browser

=head1 SYNOPSIS

  use WWW::Mechanize::Chrome;
  my $mech = WWW::Mechanize::Chrome->new();
  $mech->get('http://google.com');

  $mech->eval_in_page('alert("Hello Chrome")');
  my $png= $mech->content_as_png();

=head2 C<< WWW::Mechanize::Chrome->new %options >>

  my $mech = WWW::Mechanize::Chrome->new();

=over 4

=item B<autodie>

Control whether HTTP errors are fatal.

  autodie => 0, # make HTTP errors non-fatal

The default is to have HTTP errors fatal,
as that makes debugging much easier than expecting
you to actually check the results of every action.

=item B<port>

Specify the port where Chrome should listen

  port => 9222

=item B<log>

Specify the log level of Chrome

  log => 'OFF'   # Also INFO, WARN, DEBUG

=item B<launch_exe>

Specify the path to the Chrome executable.

The default is C<chrome> as found via C<$ENV{PATH}>.
You can also provide this information from the outside
by setting C<$ENV{chrome_EXE}>.

=item B<launch_ghostdriver>

Filename of the C<ghostdriver> Javascript code
to launch. The default is the file distributed with this module.

  launch_ghostdriver => "devel/my/ghostdriver/main.js",

=item B<launch_arg>

Specify additional parameters to the Ghostdriver script.

  launch_arg => [ "--some-new-parameter=foo" ],

=item B<cookie_file>

Cookies are not directly persisted. If you pass in a path here,
that file will be used to store or retrieve cookies.

=item B<driver>

A premade L<Selenium::Remote::Driver> object.

=item B<report_js_errors>

If set to 1, after each request tests for Javascript errors and warns. Useful
for testing with C<use warnings qw(fatal)>.

=back

=cut

sub build_command_line {
    my( $class, $options )= @_;

    $options->{ "log" } ||= 'OFF';

    $options->{ launch_exe } ||= $ENV{chrome_EXE} || 'chrome';
    $options->{ launch_arg } ||= [];
    
    $options->{port} ||= 9222;

    if ($options->{port}) {
        push @{ $options->{ launch_arg }}, "--port=$options->{ port }";
    };

    if ($options->{profile}) {
        push @{ $options->{ launch_arg }}, "--user-data-dir=$options->{ profile }";
    };
    
    push @{ $options->{ launch_arg }}, "--headless";
    push @{ $options->{ launch_arg }}, "--disable-gpu"; # temporarily needed for now

    my $program = ($^O =~ /mswin/i and $options->{ launch_exe } =~ /\s/)
                  ? qq("$options->{ launch_exe }")
                  : $options->{ launch_exe };

    my @cmd=( "|-", $program, @{ $options->{launch_arg}} );
    if( $^O =~ /mswin/i ) {
        # Windows Perl doesn't support pipe-open with list
        shift @cmd; # remove pipe-open
        @cmd= "| " . join " ", @cmd;
    };

    @cmd
};

sub new {
    my ($class, %options) = @_;

    my $localhost = '127.0.0.1';
    unless ( defined $options{ port } ) {
        # Find free port
        my $port = 9222;
        while (1) {
            $port++, next unless IO::Socket::INET->new(
                Listen    => 5,
                Proto     => 'tcp',
                Reuse     => 1,
                LocalPort => $port
            );
            last;
        }
        $options{ port } = $port;
    }

    if (! exists $options{ autodie }) { $options{ autodie } = 1 };

    if( ! exists $options{ frames }) {
        $options{ frames }= 1;
    };

    unless ($options{pid}) {
        my @cmd= $class->build_command_line( \%options );
        $options{ kill_pid } = 1;
        if( @cmd > 1 ) {
            # We can do a proper pipe-open
            my $mode = shift @cmd;
            $options{ pid } = open $options{fh}, $mode, @cmd
                or die "Couldn't launch [@cmd]: $! / $?";
        } else {
            # We can't do a proper pipe-open, so do the single-arg open
            # in the hope that everything has been set up properly
            $options{ pid } = open $options{fh}, $cmd[0]
                or die "Couldn't launch [$cmd[0]]: $! / $?";
        };

        # Just to give Chrome time to start up, make sure it accepts connections
        my $wait = time + ($options{ wait } || 20);
        while ( time < $wait ) {
            my $t = time;
            my $socket = IO::Socket::INET->new(
                PeerHost => $localhost,
                PeerPort => $options{ port },
                Proto    => 'tcp',
            );
            if( $socket ) {
                close $socket;
                sleep 1;
                last;
            };
            sleep 1 if time - $t < 1;
        }
    }

    # Connect to it
    eval {
        # XXX fixme - we need the Chrome driver here
        $options{ driver } ||= Selenium::Remote::Driver->new(
            'port' => $options{ port },
            remote_server_addr => $localhost,
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
        );
        # (Monkey)patch Selenium::Remote::Driver
        $options{ driver }->commands->get_cmds->{get}->{no_content_success}= 0;
    };

    # if Chrome started, but so slow or unresponsive that SRD cannot connect to it,
    # kill it manually to avoid waiting for it indefinitely
    if ( $@ ) {
        kill 9, delete $options{ pid } if $options{ kill_pid };
        die $@;
    }

     my $self= bless \%options => $class;

     $self->eval_in_Chrome(<<'JS');
         var page= this;
         page.errors= [];
         page.alerts= [];
         page.confirms= {};
         page.onError= function(msg, trace) {
             //_log.warn("Caught JS error", msg);
             page.errors.push({ "message": msg, "trace": trace });
         };
         page.onAlert = function(msg) {
             page.alerts.push(msg);
         };
         page.onConfirm= function(msg) {
             return page.confirms[msg];
         };
JS

     $self
};

=head2 C<< $mech->Chrome_version >>

  print $mech->Chrome_version;

Returns the version of the Chrome executable that is used.

=cut

sub Chrome_version {
    my( $self )= @_;
    $self->{Chrome_version} ||= do {
        my $version= `$self->{ launch_exe } --version`;
        $version=~ s!\s+!!g;
        $version
    };
}

=head2 C<< $mech->ghostdriver_version >>

  print $mech->ghostdriver_version;

Returns the version of the ghostdriver script that is used.

=cut

sub ghostdriver_version {
    my( $self )= @_;
    $self->{ghostdriver_version} ||= do {
        $self->eval_in_Chrome('return ghostdriver.version');
    };
}

=head2 C<< $mech->driver >>

    my $selenium= $mech->driver

Access the L<Selenium::Driver::Remote> instance connecting to Chrome.

=cut

sub driver {
    $_[0]->{driver}
};

sub autodie {
    my( $self, $val )= @_;
    $self->{autodie} = $val
        if @_ == 2;
    $_[0]->{autodie}
}

sub allow {
    my($self,%options)= @_;
    for my $opt (keys %options) {
        if( 'javascript' eq $opt ) {
            $self->eval_in_Chrome(<<'JS', $options{ $opt });
                this.settings.javascriptEnabled= arguments[0]
JS
        } else {
            warn "->allow('$opt', ...) is currently a dummy.";
        };
    };
}

=head2 C<< $mech->js_alerts() >>

  print for $mech->js_alerts();

An interface to the Javascript Alerts

Returns the list of alerts

=cut

sub js_alerts { @{ shift->eval_in_Chrome('return this.alerts') } }

=head2 C<< $mech->clear_js_alerts() >>

    $mech->clear_js_alerts();

Clears all saved alerts

=cut

sub clear_js_alerts { shift->eval_in_Chrome('this.alerts = [];') }

=head2 C<< $mech->js_errors() >>

  print $_->{message}
      for $mech->js_errors();

An interface to the Javascript Error Console

Returns the list of errors in the JEC

Maybe this should be called C<js_messages> or
C<js_console_messages> instead.

=cut

sub js_errors {
    my ($self) = @_;
    my $errors= $self->eval_in_Chrome(<<'JS');
        return this.errors
JS
    @$errors
}

=head2 C<< $mech->clear_js_errors() >>

    $mech->clear_js_errors();

Clears all Javascript messages from the console

=cut

sub clear_js_errors {
    my ($self) = @_;
    my $errors= $self->eval_in_Chrome(<<'JS');
        this.errors= [];
JS

};

=head2 C<< $mech->confirm( 'Really do this?' [ => 1 ]) >>

Records a confirmation (which is "1" or "ok" by default), to be used
whenever javascript fires a confirm dialog. If the message is not found,
the answer is "cancel".

=cut

sub confirm
{
    my ( $self, $msg, $affirmative ) = @_;
    $affirmative = 1 unless defined $affirmative;
    $affirmative = $affirmative ? 'true' : 'false';
    $self->eval_in_Chrome("this.confirms['$msg']=$affirmative;");
}

=head2 C<< $mech->eval_in_page( $str, @args ) >>

=head2 C<< $mech->eval( $str, @args ) >>

  my ($value, $type) = $mech->eval( '2+2' );

Evaluates the given Javascript fragment in the
context of the web page.
Returns a pair of value and Javascript type.

This allows access to variables and functions declared
"globally" on the web page.

This method is special to WWW::Mechanize::Chrome.

=cut

sub eval_in_page {
    my ($self,$str,@args) = @_;

    # Report errors from scope of caller
    # This feels weirdly backwards here, but oh well:
    local @Selenium::Remote::Driver::CARP_NOT
        = (@Selenium::Remote::Driver::CARP_NOT, (ref $self)); # we trust this
    local @CARP_NOT
        = (@CARP_NOT, 'Selenium::Remote::Driver', (ref $self)); # we trust this
    my $eval_in_sandbox = $self->driver->execute_script("return $str", @args);
    $self->post_process;
    return $eval_in_sandbox;
};

{
    no warnings 'once';
    *eval = \&eval_in_page;
}

=head2 C<< $mech->eval_in_Chrome $code, @args >>

  $mech->eval_in_Chrome(<<'JS', "Foobar/1.0");
      this.settings.userAgent= arguments[0]
  JS

Evaluates Javascript code in the context of Chrome.

This allows you to modify properties of Chrome.

=cut

sub eval_in_Chrome {
    my ($self, $code, @args) = @_;
    #my $tab = $self->tab;

    my $cmds= $self->driver->commands->get_cmds; # Initialize
    $cmds->{'phantomExecute'}||= {
        'method' => 'POST',
        'url' => "session/:sessionId/phantom/execute"
    };

    my $params= {
        args => \@args,
        script => $code,
    };
    $self->driver->_execute_command({ command => 'phantomExecute' }, $params);
};

sub agent {
    my($self, $ua) = @_;
    # page.settings.userAgent = 'Mozilla/5.0 (Windows NT 5.1; rv:8.0) Gecko/20100101 Firefox/7.0';
    $self->eval_in_Chrome(<<'JS', $ua);
       this.settings.userAgent= arguments[0]
JS
}

sub DESTROY {
    my $pid= delete $_[0]->{pid};

    # Purge the filehandle - we should've opened that to /dev/null anyway:
    if( my $child_out = $_[0]->{ fh }) {
        local $/;
        1 while <$child_out>;
    };

    eval {
        my $dr= delete $_[0]->{ driver };
        $dr->quit;
        undef $dr;
    };
    if( $pid ) {
        kill 'SIGKILL' => $pid;
    };
    %{ $_[0] }= (); # clean out all other held references
}

=head2 C<< $mech->highlight_node( @nodes ) >>

    my @links = $mech->selector('a');
    $mech->highlight_node(@links);
    print $mech->content_as_png();

Convenience method that marks all nodes in the arguments
with

  background: red;
  border: solid black 1px;
  display: block; /* if the element was display: none before */

This is convenient if you need visual verification that you've
got the right nodes.

There currently is no way to restore the nodes to their original
visual state except reloading the page.

=cut

sub highlight_node {
    my ($self,@nodes) = @_;
    for (@nodes) {
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

  $mech->get( $url  );

Retrieves the URL C<URL>.

It returns a faked L<HTTP::Response> object for interface compatibility
with L<WWW::Mechanize>. It seems that Selenium and thus L<Selenium::Remote::Driver>
have no concept of HTTP status code and thus no way of returning the
HTTP status code.

Note that Chrome does not support download of files.

=cut

sub update_response {
    my( $self, $phantom_res ) = @_;

    # just 1 means success
    $phantom_res = {
        status     => 200,
        statusText => 'OK',
        headers    => [{
            name  => 'x-www-mechanize-Chrome-fake-success',
            value => 1,
        }],
    } if ref($phantom_res) eq '' and $phantom_res eq '1';

    # Now add a status code of 4xx if we don't have one.
    if( ! $phantom_res->{status}) {
        $phantom_res->{status}= 400;
        $phantom_res->{statusText}= "Unknown error (added by " . __PACKAGE__ . ")";
    };

    my @headers= map {;@{$_}{qw(name value)}} @{ $phantom_res->{headers} };
    my $res= HTTP::Response->new( $phantom_res->{status}, $phantom_res->{statusText}, \@headers );

    # Should we fetch the response body?!

    delete $self->{ current_form };

    $self->{response} = $res;
    return $res
};

sub get {
    my ($self, $url, %options ) = @_;
    # We need to stringify $url so it can pass through JSON
    my $phantom_res= $self->driver->get( "$url" );
    $self->post_process;

    $self->update_response( $phantom_res );
};

=head2 C<< $mech->get_local( $filename , %options ) >>

  $mech->get_local('test.html');

Shorthand method to construct the appropriate
C<< file:// >> URI and load it into Chrome. Relative
paths will be interpreted as relative to C<$0>.

This method accepts the same options as C<< ->get() >>.

This method is special to WWW::Mechanize::Chrome but could
also exist in WWW::Mechanize through a plugin.

B<Warning>: Chrome does not handle local files well. Especially
subframes do not get loaded properly.

=cut

sub get_local {
    my ($self, $htmlfile, %options) = @_;
    require Cwd;
    require File::Spec;
    my $fn= File::Spec->file_name_is_absolute( $htmlfile )
          ? $htmlfile
          : File::Spec->rel2abs(
                 File::Spec->catfile(dirname($0),$htmlfile),
                 Cwd::getcwd(),
             );
    $fn =~ s!\\!/!g; # fakey "make file:// URL"
    my $url;
    if( $^O =~ /mswin/i ) {
        $url= "file:///$fn";
    } else {
        $url= "file://$fn";
    };
    my $res= $self->get($url, %options);
    # Chrome is not helpful with its error messages for local URLs
    if( 0+$res->headers->header_field_names and ([$res->headers->header_field_names]->[0] ne 'x-www-mechanize-Chrome-fake-success' or $self->uri ne 'about:blank')) {
        # We need to fake the content headers from <meta> tags too...
        # Maybe this even needs to go into ->get()
        $res->code( 200 );
    } else {
        $res->code( 400 ); # Must have been "not found"
    };
    $res
}

=head2 C<< $mech->post( $url, %options ) >>

B<not implemented>

Selenium currently does not allow a raw POST message
and the code for constructing a form on the fly is not working
so this method is not implemented.

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

=head2 C<< $mech->add_header( $name => $value, ... ) >>

    $mech->add_header(
        'X-WWW-Mechanize-Chrome' => "I'm using it",
        Encoding => 'text/klingon',
    );

This method sets up custom headers that will be sent with B<every> HTTP(S)
request that Chrome makes.

Note that currently, we only support one value per header.

=cut

sub add_header {
    my ($self, @headers) = @_;
    use Data::Dumper;
    #warn Dumper $headers;

    while( my ($k,$v) = splice @headers, 0, 2 ) {
        $self->eval_in_Chrome(<<'JS', , $k, $v);
            var h= this.customHeaders;
            h[arguments[0]]= arguments[1];
            this.customHeaders= h;
JS
    };
};

=head2 C<< $mech->delete_header( $name , $name2... ) >>

    $mech->delete_header( 'User-Agent' );

Removes HTTP headers from the agent's list of special headers. Note
that Chrome may still send a header with its default value.

=cut

sub delete_header {
    my ($self, @headers) = @_;

    $self->eval_in_Chrome(<<'JS', @headers);
        var headers= this.customHeaders;
        for( var i = 0; i < arguments.length; i++ ) {
            delete headers[arguments[i]];
        };
        this.customHeaders= headers;
JS
};

=head2 C<< $mech->reset_headers >>

    $mech->reset_headers();

Removes all custom headers and makes Chrome send its defaults again.

=cut

sub reset_headers {
    my ($self) = @_;
    $self->eval_in_Chrome('this.customHeaders= {}');
};

=head2 C<< $mech->res() >> / C<< $mech->response(%options) >>

    my $response = $mech->response(headers => 0);

Returns the current response as a L<HTTP::Response> object.

=cut

sub response { $_[0]->{response} };

{
    no warnings 'once';
    *res = \&response;
}

# Call croak or carp, depending on the C< autodie > setting
sub signal_condition {
    my ($self,$msg) = @_;
    if ($self->{autodie}) {
        croak $msg
    } else {
        carp $msg
    }
};

# Call croak on the C< autodie > setting if we have a non-200 status
sub signal_http_status {
    my ($self) = @_;
    if ($self->{autodie}) {
        if ($self->status and $self->status !~ /^2/ and $self->status != 0) {
            # there was an error
            croak ($self->response(headers => 0)->message || sprintf "Got status code %d", $self->status );
        };
    } else {
        # silent
    }
};

=head2 C<< $mech->success() >>

    $mech->get('http://google.com');
    print "Yay"
        if $mech->success();

Returns a boolean telling whether the last request was successful.
If there hasn't been an operation yet, returns false.

This is a convenience function that wraps C<< $mech->res->is_success >>.

=cut

sub success {
    my $res = $_[0]->response( headers => 0 );
    $res and $res->is_success
}

=head2 C<< $mech->status() >>

    $mech->get('http://google.com');
    print $mech->status();
    # 200

Returns the HTTP status code of the response.
This is a 3-digit number like 200 for OK, 404 for not found, and so on.

=cut

sub status {
    my ($self) = @_;
    return $self->response( headers => 0 )->code
};

=head2 C<< $mech->back() >>

    $mech->back();

Goes one page back in the page history.

Returns the (new) response.

=cut

sub back {
    my ($self) = @_;

    $self->driver->go_back;
}

=head2 C<< $mech->forward() >>

    $mech->forward();

Goes one page forward in the page history.

Returns the (new) response.

=cut

sub forward {
    my ($self) = @_;
    $self->driver->go_forward;
}

=head2 C<< $mech->uri() >>

    print "We are at " . $mech->uri;

Returns the current document URI.

=cut

sub uri {
    URI->new( $_[0]->driver->get_current_url )
}

=head1 CONTENT METHODS

=head2 C<< $mech->document() >>

Returns the document object as a WebElement.

This is WWW::Mechanize::Chrome specific.

=cut

sub document {
    $_[0]->driver->find_element('html','tag_name');
}

# If things get nasty, we could fall back to Chrome.webpage.plainText
# var page = require('webpage').create();
# page.open('http://somejsonpage.com', function () {
#     var jsonSource = page.plainText;
sub decoded_content {
    $_[0]->driver->get_page_source
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

sub content {
    my ($self, %options) = @_;
    $options{ format } ||= 'html';
    my $format = delete $options{ format } || 'html';

    my $content;
    if( 'html' eq $format ) {
        $content= $self->driver->get_page_source
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
        (my $ct= $meta->get_attribute('content')) =~ s/^.*;\s*charset=\s*//i;
        return $ct
            if( $ct );
    };
    $self->response->header('Content-Type');
};

=head2 C<< $mech->update_html( $html ) >>

  $mech->update_html($html);

Writes C<$html> into the current document. This is mostly
implemented as a convenience method for L<HTML::Display::MozRepl>.

=cut

sub update_html {
    my ($self,$content) = @_;
    $self->eval_in_Chrome('this.setContent(arguments[0], arguments[1])', $content);
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
    $base = $base->{href}
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
        $ct= $meta->get_attribute('content');
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

sub title {
    $_[0]->driver->get_title;
};

=head1 EXTRACTION METHODS

=head2 C<< $mech->links() >>

  print $_->text . " -> " . $_->url . "\n"
      for $mech->links;

Returns all links in the document as L<WWW::Mechanize::Link> objects.

Currently accepts no parameters. See C<< ->xpath >>
or C<< ->selector >> when you want more control.

=cut

%link_spec = (
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
            $url = $node->{ $link_spec{ $tag }->{url} };
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
            name  => $node->{name},
            base  => $base,
            url   => $url,
            text  => $node->{innerHTML},
            attrs => {},
        });

        $res
    } else {
        ()
    };
}

=head2 C<< $mech->selector( $css_selector, %options ) >>

  my @text = $mech->selector('p.content');

Returns all nodes matching the given CSS selector. If
C<$css_selector> is an array reference, it returns
all nodes matched by any of the CSS selectors in the array.

This takes the same options that C<< ->xpath >> does.

This method is implemented via L<WWW::Mechanize::Plugin::Selector>.

=cut
{
    no warnings 'once';
    *selector = \&WWW::Mechanize::Plugin::Selector::selector;
}

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

# We need to trace the path from the root element to every webelement
# because stupid GhostDriver/Selenium caches elements per document,
# and not globally, keyed by document. Switching the implied reference
# document makes lots of API calls fail :-(
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
        #use Data::Dumper;
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

=item *

C<< type >> - force the return type of the query.

  type => $mech->xpathResult('ORDERED_NODE_SNAPSHOT_TYPE'),

WWW::Mechanize::Chrome tries a best effort in giving you the appropriate
result of your query, be it a DOM node or a string or a number. In the case
you need to restrict the return type, you can pass this in.

The allowed strings are documented in the MDN. Interesting types are

  ANY_TYPE     (default, uses whatever things the query returns)
  STRING_TYPE
  NUMBER_TYPE
  ORDERED_NODE_SNAPSHOT_TYPE

=back

Returns the matched results.

You can pass in a list of queries as an array reference for the first parameter.
The result will then be the list of all elements matching any of the queries.

This is a method that is not implemented in WWW::Mechanize.

In the long run, this should go into a general plugin for
L<WWW::Mechanize>.

=cut

sub xpath {
    my( $self, $query, %options) = @_;

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

    # Save the current frame, because maybe we switch frames while searching
    # We should ideally save the complete path here, not just the current position
    if( $options{ document }) {
        warn sprintf "Document %s", $options{ document }->{id};
    };
    #my $original_frame= $self->current_frame;

    DOCUMENTS: {
        my $doc= $options{ document } || $self->document;

        # This stores the path to this document
        $doc->{__path}||= [];

        # @documents stores pairs of (containing document element, child element)
        my @documents= ($doc);

        # recursively join the results of sub(i)frames if wanted

        while (@documents) {
            my $doc = shift @documents;

            #$self->activate_container( $doc );

            my $q = join "|", @$query;
            #warn $q;

            my @found;
            # Now find the elements
            if ($options{ node }) {
                #$doc ||= $options{ node }->get_attribute( 'documentElement' );
                #if( $options{ document } and $options{ document }->get_tag_name =~ /^i?frame$/i) {
                #    $self->driver->switch_to_frame( $options{ document });
                #} elsif( $options{ document } and $options{ document }->get_tag_name =~ /^html$/i) {
                #    $self->driver->switch_to_frame();
                #} elsif( $options{ document }) {
                #    die sprintf "Don't know how to switch to a '%s'", $options{ document }->get_tag_name;
                #};
                @found= map { $self->driver->find_child_elements( $options{ node }, $_ => 'xpath' ) } @$query;
            } else {
                #warn "Collecting frames";
                #my $tag= $doc->get_tag_name;
                #warn "Searching $doc->{id} for @$query";
                @found= map { $self->driver->find_elements( $_ => 'xpath' ) } @$query;
                if( ! @found ) {
                    #warn "Nothing found matching @$query in frame";
                    #warn $self->content;
                    #$self->driver->switch_to_frame();
                };
                #$self->driver->switch_to_frame();
                #warn $doc->get_text;
            };

            # Remember the path to each found element
            for( @found ) {
                # We reuse the reference here instead of copying the list. So don't modify the list.
                $_->{__path}= $doc->{__path};
            };

            push @res, @found;

            # A small optimization to return if we already have enough elements
            # We can't do this on $return_first as there might be more elements
            #if( @res and $options{ return_first } and grep { $_->{resultSize} } @res ) {
            #    @res= grep { $_->{resultSize} } @res;
            #    last DOCUMENTS;
            #};
            use Data::Dumper;
            #warn Dumper \@documents;
            if ($options{ frames } and not $options{ node }) {
                #warn "Expanding subframes";
                #warn ">Expanding below " . $doc->get_tag_name() . ' - ' . $doc->get_attribute('title');
                #local $nesting .= "--";
                my @d; # = $self->expand_frames( $options{ frames }, $doc );
                #warn sprintf("Found %s %s pointing to %s", $_->get_tag_name, $_->{id}, $_->get_attribute('src')) for @d;
                push @documents, @d;
            };
        };
    };

    # Restore frame context
    #warn "Switching back";
    #$self->activate_container( $original_frame );

    #@res

    # Determine if we want only one element
    #     or a list, like WWW::Mechanize::Chrome

    if (! $zero_allowed and @res == 0) {
        $self->signal_condition( "No elements found for $options{ user_info }" );
    };
    if (! $two_allowed and @res > 1) {
        #$self->highlight_node(@res);
        warn $_->get_text() || '<no text>' for @res;
        $self->signal_condition( (scalar @res) . " elements found for $options{ user_info }" );
    };

    $return_first_element ? $res[0] : @res

}

=head2 C<< $mech->by_id( $id, %options ) >>

  my @text = $mech->by_id('_foo:bar');

Returns all nodes matching the given ids. If
C<$id> is an array reference, it returns
all nodes matched by any of the ids in the array.

This method is equivalent to calling C<< ->xpath >> :

    $self->xpath(qq{//*[\@id="$_"], %options)

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
    } elsif (ref $name and blessed($name) and $name->can('click')) {
        $options{ dom } = $name;
    } elsif (ref $name eq 'HASH') { # options
        %options = %$name;
    } else {
        $options{ name } = $name;
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

    $buttons[0]->click();
    $self->post_process;

    if (defined wantarray) {
        return $self->response
    };
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

  pre
  post
  name
  value

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
        #warn $query;
        @fields = $self->xpath($query,%options);
    };
    @fields
}

sub escape
{
    my $s = shift;
    $s =~ s/(["\\])/\\$1/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    return $s;
}

sub get_set_value {
    my ($self,%options) = @_;
    my $set_value = exists $options{ value };
    my $value = delete $options{ value };
    my $pre   = delete $options{pre}  || $self->{pre_value};
    my $post  = delete $options{post} || $self->{post_value};
    my $name  = delete $options{ name };
    my @fields = $self->_field_by_name(
                     name => $name,
                     user_info => "input with name '$name'",
                     %options );
    $pre = [$pre]
        if (! ref $pre);
    $post = [$post]
        if (! ref $post);

    if ($fields[0]) {
        my $tag = $fields[0]->get_tag_name();
        if ($set_value) {
            #for my $ev (@$pre) {
            #    $fields[0]->__event($ev);
            #};

            my $get= $self->Chrome_elementToJS();
            my $val= escape($value);
            my $bool = $value ? 'true' : 'false';
            my $js= <<JS;
                var g=$get;
                var el=g("$fields[0]->{id}");
                if (el.type=='checkbox')
                   el.checked=$bool;
                else
                   el.value="$val";
JS
            $js= quotemeta($js);
            $self->eval("eval('$js')"); # for some reason, Selenium/Ghostdriver don't like the JS as plain JS

            #for my $ev (@$post) {
            #    $fields[0]->__event($ev);
            #};
        };
        # What about 'checkbox'es/radioboxes?

        # Don't bother to fetch the field's value if it's not wanted
        return unless defined wantarray;

        # We could save some work here for the simple case of single-select
        # dropdowns by not enumerating all options
        if ('SELECT' eq uc $tag) {
            my @options = $self->xpath('.//option', node => $fields[0] );
            my @values = map { $_->{value} } grep { $_->{selected} } @options;
            if (wantarray) {
                return @values
            } else {
                return $values[0];
            }
        } else {
            return $fields[0]->{value}
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

sub submit {
    my ($self,$dom_form) = @_;
    $dom_form ||= $self->current_form;
    if ($dom_form) {
        $dom_form->submit();
        $self->signal_http_status;

        $self->clear_current_form;
        1;
    } else {
        croak "I don't know which form to submit, sorry.";
    }
    $self->post_process;
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
set_fields and click methods into one higher level call. Its arguments are
a list of key/value pairs, all of which are optional.

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

sub submit_form {
    my ($self,%options) = @_;

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

sub set_fields {
    my ($self, %fields) = @_;
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

=head2 C<< $mech->expand_frames( $spec ) >>

  my @frames = $mech->expand_frames();

Expands the frame selectors (or C<1> to match all frames)
into their respective Chrome nodes according to the current
document. All frames will be visited in breadth first order.

This is mostly an internal method.

=cut

sub expand_frames {
    my ($self, $spec, $document) = @_;
    $spec ||= $self->{frames};
    my @spec = ref $spec ? @$spec : $spec;
    $document ||= $self->document;

    if (! ref $spec and $spec !~ /\D/ and $spec == 1) {
        # All frames
        @spec = qw( frame iframe );
    };

    # Optimize the default case of only names in @spec
    my @res;
    if (! grep {ref} @spec) {
        @res = $self->selector(
                        \@spec,
                        document => $document,
                        frames => 0, # otherwise we'll recurse :)
                    );
    } else {
        @res =
            map { #warn "Expanding $_";
                    ref $_
                  ? $_
                  # Just recurse into the above code path
                  : $self->expand_frames( $_, $document );
            } @spec;
    }

    @res
};


=head2 C<< $mech->current_frame >>

    my $last_frame= $mech->current_frame;
    # Switch frame somewhere else

    # Switch back
    $mech->activate_container( $last_frame );

Returns the currently active frame as a WebElement.

This is mostly an internal method.

See also

L<http://code.google.com/p/selenium/issues/detail?id=4305>

Frames are currently not really supported.

=cut

sub current_frame {
    my( $self )= @_;
    my @res;
    my $current= $self->make_WebElement( $self->eval('window'));
    warn sprintf "Current_frame: bottom: %s", $current->{id};

    # Now climb up until the root window
    my $f= $current;
    my @chain;
    warn "Walking up to root document";
    while( $f= $self->driver->execute_script('return arguments[0].frameElement', $f )) {
        $f= $self->make_WebElement( $f );
        unshift @res, $f;
        warn sprintf "One more level up, now in %s",
            $f->{id};
        warn $self->driver->execute_script('return arguments[0].title', $res[0]);
        unshift @chain,
            sprintf "Frame chain: %s %s", $res[0]->get_tag_name, $res[0]->{id};
        # Activate that frame
        $self->switch_to_parent_frame();
        warn "Going up once more, maybe";
    };
    warn "Chain complete";
    warn $_
        for @chain;

    # Now fake the element into
    my $el= $self->make_WebElement( $current );
    for( @res ) {
        warn sprintf "Path has (web element) id %s", $_->{id};
    };
    $el->{__path}= \@res;
    $el
}

sub switch_to_parent_frame {
    #use JSON;
    my ( $self ) = @_;

    $self->{driver}->{commands}->{'switchToParentFrame'}||= {
        'method' => 'POST',
        'url' => "session/:sessionId/frame/parent"
    };

    #my $json_null = JSON::null;
    my $params;
    #$id = ( defined $id ) ? $id : $json_null;

    my $res    = { 'command' => 'switchToParentFrame' };
    return $self->driver->_execute_command( $res, $params );
}

sub make_WebElement {
    my( $self, $e )= @_;
    return $e
        if( blessed $e and $e->isa('Selenium::Remote::WebElement'));
    my $res= Selenium::Remote::WebElement->new( $e->{WINDOW} || $e->{ELEMENT}, $self->driver );
    croak "No id in " . Dumper $res
        unless $res->{id};

    $res
}

=head1 CONTENT RENDERING METHODS

=head2 C<< $mech->content_as_png( [\%coordinates ] ) >>

    my $png_data = $mech->content_as_png();

    # Create scaled-down 480px wide preview
    my $png_data = $mech->content_as_png(undef, { width => 480 });

Returns the given tab or the current page rendered as PNG image.

All parameters are optional.

=over 4

=item C< \%coordinates >

If the coordinates are given, that rectangle will be cut out.
The coordinates should be a hash with the four usual entries,
C<left>,C<top>,C<width>,C<height>.

=back

This method is specific to WWW::Mechanize::Chrome.

Currently, the data transfer between Chrome and Perl
is done Base64-encoded.

=cut

sub content_as_png {
    my ($self, $rect) = @_;
    $rect ||= {};

    if( scalar keys %$rect ) {

        $self->eval_in_Chrome( 'this.clipRect= arguments[0]', $rect );
    };

    return $self->render_content( format => 'png' );
};

=head2 C<< $mech->viewport_size >>

  print Dumper $mech->viewport_size;
  $mech->viewport_size({ width => 1388, height => 792 });

Returns (or sets) the new size of the viewport (the "window").

=cut

sub viewport_size {
    my( $self, $new )= @_;

    $self->eval_in_Chrome( <<'JS', $new );
        if( arguments[0]) {
            this.viewportSize= arguments[0];
        };
        return this.viewportSize;
JS
};

=head2 C<< $mech->element_as_png( $element ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my $i_want_this = $mech->element_as_png($shiny);

Returns PNG image data for a single element

=cut

sub element_as_png {
    my ($self, $element) = @_;

    my $cliprect = $self->element_coordinates( $element );

    my $code = <<'JS';
       var old= this.clipRect;
       this.clipRect= arguments[0];
JS

    my $old= $self->eval_in_Chrome( $code, $cliprect );
    my $png= $self->content_as_png();
    #warn Dumper $old;
    $self->eval_in_Chrome( $code, $old );
    $png
};

=head2 C<< $mech->render_element( %options ) >>

    my $shiny = $mech->selector('#shiny', single => 1);
    my $i_want_this= $mech->render_element(
        element => $shiny,
        format => 'pdf',
    );

Returns the data for a single element
or writes it to a file. It accepts
all options of C<< ->render_content >>.

=cut

sub render_element {
    my ($self, %options) = @_;
    my $element= delete $options{ element }
        or croak "No element given to render.";

    my $cliprect = $self->element_coordinates( $element );

    my $code = <<'JS';
       var old= this.clipRect;
       this.clipRect= arguments[0];
JS

    my $old= $self->eval_in_Chrome( $code, $cliprect );
    my $res= $self->render_content(
        %options
    );
    #warn Dumper $old;
    $self->eval_in_Chrome( $code, $old );
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
    my $cliprect = $self->eval('arguments[0].getBoundingClientRect()', $element );
};

=head2 C<< $mech->render_content(%options) >>

    my $pdf_data = $mech->render( format => 'pdf' );

    $mech->render_content(
        format => 'jpg',
        filename => '/path/to/my.jpg',
    );

Returns the current page rendered in the specified format
as a bytestring or stores the current page in the specified
filename.

The filename must be absolute. We are dealing with external processes here!

This method is specific to WWW::Mechanize::Chrome.

Currently, the data transfer between Chrome and Perl
is done through a temporary file, so directly using
the C<filename> option may be faster.

=cut

sub render_content {
    my ($self, %options) = @_;
    #$rect ||= {};
    #$target_rect ||= {};
    my $outname= $options{ filename };
    my $format= $options{ format };
    my $wantresult;

    my @delete;
    if( ! $outname) {
        require File::Temp;
        (my $fh, $outname)= File::Temp::tempfile();
        close $fh;
        push @delete, $outname;
        $wantresult= 1;
    };
    require File::Spec;
    $outname= File::Spec->rel2abs($outname, '.');

    $self->eval_in_Chrome(<<'JS', $outname, $format);
        var outname= arguments[0];
        var format= arguments[1];
        this.render( outname, { "format": format });
JS

    my $result;
    if( $wantresult ) {
        open my $fh, '<', $outname
            or die "Couldn't read tempfile '$outname': $!";
        binmode $fh, ':raw';
        local $/;
        $result= <$fh>;
    };

    for( @delete ) {
        unlink $_
            or warn "Couldn't clean up tempfile: $_': $!";
    };
    $result
}

=head2 C<< $mech->content_as_pdf(%options) >>

    my $pdf_data = $mech->content_as_pdf();

    $mech->content_as_pdf(
        filename => '/path/to/my.pdf',
    );

Returns the current page rendered in PDF format as a bytestring.

This method is specific to WWW::Mechanize::Chrome.

Currently, the data transfer between Chrome and Perl
is done through a temporary file, so directly using
the C<filename> option may be faster.

=cut

sub content_as_pdf {
    my ($self, %options) = @_;

    return $self->render_content( format => 'pdf', %options );
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

=head2 C<< $mech->Chrome_elementToJS >>

Returns the Javascript fragment to turn a Selenium::Remote::Chrome
id back to a Javascript object.

=cut

sub Chrome_elementToJS {
    <<'JS'
    function(id,doc_opt){
        var d = doc_opt || document;
        var c= d['$wdc_'];
        return c[id]
    };
JS
}

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
    Carp::carp("javascript error: @errors") ;
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

Selenium does not support POST requests

=back

=head1 TODO

=over 4

=item *

Add C<< limit >> parameter to C<< ->xpath() >> to allow an early exit-case
when searching through frames.

=item *

Implement downloads via

L<https://perlmonks.org/?node_id=1151151>

=item *

Implement download progress

=back

=head1 INSTALLING

=over 4

=back

=head2 Install the C<Chrome> executable

=over

=item *

Installing on Ubuntu

Version: 1.9.8
Platform: x86_64

Install or update latest system software:

C<< sudo apt-get update >>

C<< sudo apt-get install build-essential chrpath libssl-dev libxft-dev >>

Install the following packages needed by Chrome:

C<< sudo apt-get install libfreetype6 libfreetype6-dev >>

C<< sudo apt-get install libfontconfig1 libfontconfig1-dev >>

Get Chrome from the L<website|http://Chrome.org/>

C<< cd ~ >>

C<< export PHANTOM_JS="Chrome-1.9.8-linux-x86_64" >>

C<< wget https://bitbucket.org/ariya/Chrome/downloads/$PHANTOM_JS.tar.bz2 >>

C<< sudo tar xvjf $PHANTOM_JS.tar.bz2 >>

Once downloaded move Chrome folder:

C<< sudo mv $PHANTOM_JS /usr/local/share >>

C<< sudo ln -sf /usr/local/share/$PHANTOM_JS/bin/Chrome /usr/local/bin >>

C<< sudo ln -sf /usr/local/share/$PHANTOM_JS/bin/Chrome /usr/bin/Chrome >>

Test it has been installed on your system:

C<< Chrome --version >>

=back

=head1 SEE ALSO

=over 4

=item *

L<http://Chrome.org> - the Chrome homepage

=item *

L<https://github.com/detro/ghostdriver> - the ghostdriver homepage

=item *

L<WWW::Mechanize> - the module whose API grandfathered this module

=item *

L<WWW::Scripter> - another WWW::Mechanize-workalike with Javascript support

=item *

L<WWW::Mechanize::Firefox> - a similar module with a visible application

=back

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-Chrome>.

=head1 SUPPORT

The public support forum of this module is
L<https://perlmonks.org/>.

=head1 TALKS

I've given a talk about this module at Perl conferences:

L<German Perl Workshop 2014, German|http://corion.net/talks/WWW-Mechanize-Chrome/www-mechanize-Chrome.de.html>

L<YAPC::Europe 2014, English|http://corion.net/talks/WWW-Mechanize-Chrome/www-mechanize-Chrome.en.html>

L<Talk on Youtube|https://www.youtube.com/watch?v=lH3Fhw6b5BI>

=for html
<iframe id="ytplayer" type="text/html" width="640" height="390"
  src="https://www.youtube.com/watch?v=lH3Fhw6b5BI"
  frameborder="0"/>

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=WWW-Mechanize-Chrome>
or via mail to L<www-mechanize-Chrome-Bugs@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2014-2016 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

This distribution includes a modified copy of the ghostdriver code,
which is released under the same terms as the ghostdriver code itself.
The terms of the ghostdriver code are the BSD license, as found at
L<https://github.com/detro/ghostdriver/blob/master/LICENSE.BSD>:

    Copyright (c) 2014, Ivan De Marino <http://ivandemarino.me>
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification,
    are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
    this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
    ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
    ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The ghostdriver code includes the Selenium WebDriver fragments.

=cut
