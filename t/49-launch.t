#!perl
use warnings;
use strict;
use Test::More tests => 5;

use Log::Log4perl qw(:easy);

use WWW::Mechanize::Chrome;

Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

my ($program,$msg) = WWW::Mechanize::Chrome->find_executable('path/another-nonexistent');
is $program, undef, "Nonexisting program does not get found";
like $msg, qr/^No executable like '.*' found$/, "We signal the correct error";

{
    local $ENV{CHROME_BIN} = 'bar';
    is_deeply [WWW::Mechanize::Chrome->default_executable_names('foo')],
              ['bar','foo'],
              "CHROME_BIN overrides hardcoded values";
};

{
    local $ENV{CHROME_BIN};
    my $lives = eval {
        WWW::Mechanize::Chrome->new(
            launch_exe => 'program.that.doesnt.exist',
        );
        1;
    };
    my $err = $@;
    is $lives, undef, "We die if we can't find the executable in \$ENV{PATH}";
    like $@, qr/No executable like '.*?' found in/, "We signal the error condition";
};