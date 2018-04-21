#!perl -w
use strict;
use Test::More;
use Cwd;
use URI::file;
use File::Basename;
use File::Spec;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

use lib '.';
use Test::HTTP::LocalServer;

use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 4*@instances;
};

sub new_mech {
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

my $server = Test::HTTP::LocalServer->spawn(
    #debug => 1
);

sub save {
    my ($data,$filename) = @_;
    open my $fh, '>', $filename
        or die "Couldn't create '$filename': $!";
    binmode $fh;
    print {$fh} $data;
};

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 4, sub {

    my ($browser_instance, $mech) = @_;

    isa_ok $mech, 'WWW::Mechanize::Chrome';

    my @frames;
    my $num = 1;
    $mech->setScreenFrameCallback( sub {
        save $_[1]->{data}, sprintf 'frame-%03d.png', $num++;
        push @frames, $_[1]
    });

    # First get a clean check without the changed headers
    my ($site,$estatus) = ($server->url,200);
    my $res = $mech->get($site);
    isa_ok $res, 'HTTP::Response', "Response";
    
    $mech->field('query','Hello World');

    # Wait for things to settle down?!
    $mech->sleep( 5 );
    
    $mech->setScreenFrameCallback( undef );
    cmp_ok 0+@frames, '>', 0, "We 'captured' at least one frame";
    
    my @not_png = grep {! $_->{data} =~ /^.PNG/} @frames;
    if( ! is 0+@not_png, 0, "All frames are PNG frames" ) {
        diag substr($_,0,4) for @not_png;
    }
});

$server->kill;
undef $server;
