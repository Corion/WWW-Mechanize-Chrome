#!perl -w
use strict;
use Test::More;
use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib './inc', '../inc', '.';
use Test::HTTP::LocalServer;

use t::helper;

#Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR
Log::Log4perl->easy_init($TRACE);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my $instance_port = 9222;
my @instances = t::helper::browser_instances();

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => 3*@instances;
};

sub new_mech {
    my $m = WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

#my $server = Test::HTTP::LocalServer->spawn(
#    #debug => 1,
#);

t::helper::run_across_instances(\@instances, $instance_port, \&new_mech, 3, sub {
    my ($browser_instance, $mech) = @_;

    SKIP: {
        my $version = $mech->chrome_version;

        if( $version =~ /\b(\d+)\b/ and $1 < 62 ) {
            skip "Chrome before v62 doesn't know about online/offline mode...", 3;
		} else {
			#$mech->get($server->url);
			$mech->get_local('50-click.html');
			
			my ($value,$type);
			#my ($value, $type) = $mech->eval_in_page('window.navigator.connection.effectiveType');
			#is( $value, '4g', "We are online");
			($value, $type) = $mech->eval_in_page('window.navigator.onLine');
			is( $value, JSON::PP::true, "We are online (.onLine)");
			
			$mech->emulateNetworkConditions(
				offline => $JSON::PP::true,
			);
			#($value, $type) = $mech->eval('navigator.connection.effectiveType');
			#is( $value, 'offline', "We are offline");
			($value, $type) = $mech->eval_in_page('window.navigator.onLine');
			is( $value, JSON::PP::false, "We are offline (.onLine)");
			
			# But this one still succeeds, as do outbound requests :-(
			#$mech->get($server->url);

			$mech->emulateNetworkConditions(
				offline => $JSON::PP::false,
			);
			#($value, $type) = $mech->eval('navigator.connection.effectiveType');
			#is( $value, '4g', "We are online again");
			($value, $type) = $mech->eval_in_page('window.navigator.onLine');
			is( $value, JSON::PP::true, "We are online (.onLine)");
		}
	}

    undef $mech;
});