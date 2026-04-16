#!perl -w

#use warnings;
use strict;
use Test::More;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;
use lib '.';
use t::helper;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

# What instances of Chrome will we try?
my @instances = t::helper::browser_instances();
my $testcount = 20;

if (my $err = t::helper::default_unavailable) {
    plan skip_all => "Couldn't connect to Chrome: $@";
    exit
} else {
    plan tests => $testcount*@instances;
};

sub new_mech {
    t::helper::need_minimum_chrome_version( '62.0.0.0', @_ );
    WWW::Mechanize::Chrome->new(
        autodie => 1,
        @_,
    );
};

t::helper::run_across_instances(\@instances, \&new_mech, $testcount, sub {
    my ($browser_instance, $mech) = @_;

    t::helper::set_watchdog($t::helper::is_slow ? 180 : 60);

#my $uri = URI::file->new_abs( 't/select.html' )->as_string;
my $response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );

my ($sendsingle, @sendmulti, %sendsingle, %sendmulti,
    $rv, $return, @return, @singlereturn, $form);
# possible values are: aaa, bbb, ccc, ddd
$sendsingle = 'aaa';
@sendmulti = qw(bbb ccc);
@singlereturn = ($sendmulti[0]);
%sendsingle = (n => 1);
%sendmulti = (n => [2, 3]);

ok(t::helper::safe_form_number($mech, 1), 'set form to number 1');
$form = $mech->current_form();

# Multi-select

# pass multiple values to a multi select
$mech->select('multilist', \@sendmulti);
@return = t::helper::safe_value($mech, 'multilist', { all => 1 });
is_deeply(\@return, \@sendmulti, 'multi->multi value is ' . join(' ', @sendmulti));

$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$mech->select('multilist', \%sendmulti);
@return = t::helper::safe_value($mech, 'multilist', { all => 1 });
is_deeply(\@return, \@sendmulti, 'multi->multi value is ' . join(' ', @sendmulti));

# pass a single value to a multi select
$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$mech->select('multilist', $sendsingle);
#$return = $form->param('multilist');
$return = t::helper::safe_value($mech, 'multilist', { all => 1 });
is($return, $sendsingle, "single->multi value is '$sendsingle'");

$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$mech->select('multilist', \%sendsingle);
$return = t::helper::safe_value($mech, 'multilist', { all => 1 });
is($return, $sendsingle, "single->multi value is '$sendsingle'");


# Single select

# pass multiple values to a single select (only the _first_ should be set)
$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$mech->select('singlelist', \@sendmulti);
@return = t::helper::safe_value($mech, 'singlelist');
is_deeply(\@return, \@singlereturn, 'multi->single value is ' . join(' ', @singlereturn));

$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$mech->select('singlelist', \%sendmulti);
@return = t::helper::safe_value($mech, 'singlelist');
is_deeply(\@return, \@singlereturn, 'multi->single value is ' . join(' ', @singlereturn));


# pass a single value to a single select
$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$rv = $mech->select('singlelist', $sendsingle);
$return = t::helper::safe_value($mech, 'singlelist');
is($return, $sendsingle, "single->single value is '$sendsingle'");

$response = t::helper::safe_get_local($mech,  'select.html' );
ok( $response->is_success, "Fetched select.html" );
$rv = $mech->select('singlelist', \%sendsingle);
$return = t::helper::safe_value($mech, 'singlelist');
is($return, $sendsingle, "single->single value is '$sendsingle'");

# test return value from $mech->select
is($rv, 1, 'return 1 after successful select');

undef $rv;
my $lived = eval {
    $rv = $mech->select('missing_list', 1);
    1;
};
is $lived, 1, 'We can ->select() on a missing field'
    or diag $@;
is($rv, undef, 'return undef after failed select');

});

alarm(0);
