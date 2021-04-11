package WWW::Mechanize::Firefox;
use strict;
use warnings;
use Moo 2;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

extends 'WWW::Mechanize::Chrome';

around build_command_line => sub( $orig, $class, $options ) {
    my @program_names = $class->default_executable_names( $options->{launch_exe} );

    my( $program, $error) = $class->find_executable(\@program_names);
    croak $error if ! $program;

    # Convert the path to an absolute filename, so we can chdir() later
    $program = File::Spec->rel2abs( $program ) || $program;

    $options->{ launch_arg } ||= [];

    # At least for the time being, we don't allow connecting to an existing
    # browser session
    push @{ $options->{ launch_arg }}, '--new-instance';

    if ($options->{profile}) {
        push @{ $options->{ launch_arg }}, "--profile", $options->{ profile };
    };

    if( $options->{pipe}) {
        push @{ $options->{ launch_arg }}, "--remote-debugging-pipe";
    } else {

        $options->{port} //= 9222
            if ! exists $options->{port};

        if (exists $options->{port}) {
            $options->{port} ||= 0;
            push @{ $options->{ launch_arg }}, "--remote-debugging-port=$options->{ port }";
        };

        if ($options->{listen_host}) {
            push @{ $options->{ launch_arg }}, "--remote-debugging-address==$options->{ listen_host }";
        };
    };

    if ($options->{incognito}) {
        push @{ $options->{ launch_arg }}, "--incognito";
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



1;
