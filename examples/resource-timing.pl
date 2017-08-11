use strict;
use File::Spec;
use File::Basename 'dirname';
use WWW::Mechanize::Chrome;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my $mech = WWW::Mechanize::Chrome->new(
    headless => 1,
);

use Data::Dumper;

my $url_loaded = $mech->add_listener('Network.responseReceived', sub {
    my( $info ) = @_;
    #warn Dumper $info;
    warn "Loaded URL $info->{params}->{response}->{url}: $info->{params}->{response}->{status}";
    warn "Resource timing: " . Dumper $info->{params}->{response}->{timing};
});

my $url= 'http://127.0.0.1:5000/index.html';
print "Loading $url\n";
$mech->get($url);
