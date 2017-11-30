package WWW::Mechanize::Chrome::DSL;
use strict;
use WWW::Mechanize::Chrome;
use Object::Import;
use Carp qw(croak);

our $VERSION = '0.08';

our @CARP_NOT = (qw[
    WWW::Mechanize::Chrome
]);

=head1 NAME

WWW::Mechanize::Chrome::DSL - Domain Specific Language for short scripts

=head1 SYNOPSIS

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($ERROR);
    use WWW::Mechanize::Chrome::DSL '$mech';

    get 'http://google.de';
    
    my @links = selector('a');
    print $_->{innerHTML},"\n" for @links;
    
    click($links[0]);
    
    print content;

This module exports all methods of one WWW::Mechanize::Chrome
object as subroutines. That way, you can write short scripts without
cluttering every line with C<< $mech-> >>.

This module is highly experimental and might vanish from the distribution
again if I find that it is useless.

=cut

sub import {
    my ($class, %options);
    if (@_ == 2) {
        ($class, $options{ name }) = @_;
    } else {
        ($class, %options) = @_;
    };
    my $target = delete $options{ target } || caller;
    my $name = delete $options{ name } || '$mech';
    my $mech = WWW::Mechanize::Chrome->new(%options);
    
    $name =~ s/^[\$]//
        or croak 'Variable name must start with $';
    {
        no strict 'refs';
        *{"$target\::$name"} = \$mech;
        import Object::Import \${"$target\::$name"},
                              deref => 1,
                              target => $target,
                              ;
    };
};

1;

=head1 AUTHORS

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2009-2017 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
