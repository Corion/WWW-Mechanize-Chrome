package WWW::Mechanize::Edge;
use Carp qw(croak);
use Moo;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

extends 'WWW::Mechanize::Chrome';

our $VERSION = '0.22';

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

1;
