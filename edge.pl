#!perl -w
package WWW::Mechanize::Edge;
use Carp qw(croak);
use Moo;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

extends 'WWW::Mechanize::Chrome';

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
        #: $^O =~ /darwin/i ? 'Google Chrome'
        #: ('google-chrome', 'chromium-browser')
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

1;
package main;
use strict;
use Log::Log4perl ':easy';
Log::Log4perl->easy_init($TRACE);

my $mech = WWW::Mechanize::Edge->new();

$mech->get('https://example.com');

