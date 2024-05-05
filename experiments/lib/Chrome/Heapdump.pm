package Chrome::Heapdump 0.01;
use 5.020;
use Moo 2;

use experimental 'signatures';
use JSON::XS 'decode_json';

has 'data' => ( is => 'ro' );

sub from_string( $package, $str ) {
    $package->new({ data => decode_json( $str ) })
}

1;
