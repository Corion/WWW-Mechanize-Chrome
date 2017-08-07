#!perl -w
use strict;
use Test::More;
use WWW::Mechanize::Chrome;
use lib 'inc', '../inc', '.';
use File::Temp qw(tempfile);
use Test::HTTP::LocalServer;

use t::helper;

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();
my @tests= (
    { format => 'pdf', like => qr/^%PDF-/ },
    { format => 'png', like => qr/^.PNG/, },
    #{ format => 'jpg', like => qr/^......JFIF/, },
);

my $testcount = (1+@tests*2);

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount * @instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my @delete;
END {
    for( @delete ) {
        unlink $_
            or diag "Couldn't remove tempfile '$_': $!";
    }
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    $mech->get_local('50-click.html');
    for my $test ( @tests ) {
        my $format= $test->{format};
        my $content= eval { $mech->render_content( format => $format ); };
        SKIP: {
            if( $@ ) {
                skip "$@", 2;
            };

            my $shortcontent = substr( $content, 0, 30 );
            like $shortcontent, $test->{like}, "->render_content( format => '$format' )"
                or diag $shortcontent;
            my @delete;
            my( $tempfh,$outfile )= tempfile;
            close $tempfh;
            push @delete, $outfile;
            $mech->render_content( format => $format, filename => $outfile );
            my($res, $reason)= (undef, "Outfile '$outfile' was not created");
            if(-f $outfile) {
                if( open my $fh, '<:raw', $outfile ) {
                    local $/;
                    my $content= <$fh>;
                    $res= $content =~ $test->{like}
                        or $reason= "Content did not match /$test->{like}/: " . substr($content,0,10);
                } else {
                    $reason= "Couldn't open '$outfile': $!";
                };
            };
            ok $res, "->render_content to file"
                or diag $reason;
        };
    };
});
