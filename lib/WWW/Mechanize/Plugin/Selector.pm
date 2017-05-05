package WWW::Mechanize::Plugin::Selector;
use strict;
use vars qw($VERSION);
$VERSION= '0.16';
use HTML::Selector::XPath 'selector_to_xpath';

=head1 SYNOPSIS

=head1 NAME

WWW::Mechanize::Plugin::Selector - CSS selector method for WWW::Mechanize

=cut

=head1 ADDED METHODS

=head2 C<< $mech->selector( $css_selector, %options ) >>

  my @text = $mech->selector('p.content');

Returns all nodes matching the given CSS selector. If
C<$css_selector> is an array reference, it returns
all nodes matched by any of the CSS selectors in the array.

This takes the same options that C<< ->xpath >> does.

=cut

sub selector {
    my ($self,$query,%options) = @_;
    $options{ user_info } ||= "CSS selector '$query'";
    if ('ARRAY' ne (ref $query || '')) {
        $query = [$query];
    };
    my $root = $options{ node } ? './' : '';
    my @q = map { selector_to_xpath($_, root => $root) } @$query;
    $self->xpath(\@q, %options);
};

1;