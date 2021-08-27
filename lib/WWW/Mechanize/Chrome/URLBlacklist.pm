package WWW::Mechanize::Chrome::URLBlacklist;
use Moo 2;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

our $VERSION = '0.68';

=head1 NAME

WWW::Mechanize::Chrome::URLBlacklist - blacklist URLs from fetching

=head1 SYNOPSIS

    use WWW::Mechanize::Chrome;
    use WWW::Mechanize::Chrome::URLBlacklist;

    my $mech = WWW::Mechanize::Chrome->new();
    my $bl = WWW::Mechanize::Chrome::URLBlacklist->new(
        blacklist => [
            qr!\bgoogleadservices\b!,
        ],
        whitelist => [
            qr!\bcorion\.net\b!,
        ],

        # fail all unknown URLs
        default => 'failRequest',
        # allow all unknown URLs
        # default => 'continueRequest',

        on_default => sub {
            warn "Ignored URL $_[0] (action was '$_[1]')",
        },
    );
    $bl->enable($mech);

=head1 DESCRIPTION

This module allows an easy approach to whitelisting/blacklisting URLs
so that Chrome does not make requests to the blacklisted URLs.

=head1 ATTRIBUTES

=head2 C<< whitelist >>

Arrayref containing regular expressions of URLs to always allow fetching.

=cut

has 'whitelist' => (
    is => 'lazy',
    default => sub { [] },
);

=head2 C<< blacklist >>

Arrayref containing regular expressions of URLs to always deny fetching unless
they are matched by something in the C<whitelist>.

=cut

has 'blacklist' => (
    is => 'lazy',
    default => sub { [] },
);

=head2 C<< default >>

  default => 'continueRequest'

The action to take if an URL appears neither in the C<whitelist> nor
in the C<blacklist>. The default is C<continueRequest>. If you want to block
all unknown URLs, use C<failRequest>

=cut

has 'default' => (
    is => 'rw',
    default => 'continueRequest',
);

=head2 C<< on_default >>

  on_default => sub {
      my( $url, $action ) = @_;
      warn "Unknown URL <$url>";
  };

This callback is invoked for every URL that is neither in the whitelist nor
in the blacklist. This is useful to see what URLs are still missing a category.

=cut


has 'on_default' => (
    is => 'rw',
);

=head2 C<< _mech >>

(internal) The WWW::Mechanize::Chrome instance we are connected to

=cut

has '_mech' => (
    is => 'rw',
);

=head2 C<< _request_listener >>

(internal) The request listener created by WWW::Mechanize::Chrome while listening
for URL messages

=cut

has '_request_listener' => (
    is => 'rw',
);

=head1 METHODS

=head2 C<< ->new >>

  my $bl = WWW::Mechanize::Chrome::URLBlacklist->new(
      blacklist => [
          qr!\bgoogleadservices\b!,
          qr!\ioam\.de\b!,
          qr!\burchin\.js$!,
          qr!.*\.(?:woff|ttf)$!,
          qr!.*\.css(\?\w+)?$!,
          qr!.*\.png$!,
          qr!.*\bfavicon.ico$!,
      ],
  );
  $bl->enable( $mech );

Creates a new instance of a blacklist, but does B<not> activate it yet.
See C<< ->enable >> for that.

=cut

sub on_requestPaused( $self, $info ) {
    my $id = $info->{params}->{requestId};
    my $request = $info->{params}->{request};
    my $mech = $self->_mech;

    if( grep { $request->{url} =~ /$_/ } @{ $self->whitelist } ) {
        #warn "Whitelisted URL $request->{url}";
        $mech->target->send_message('Fetch.continueRequest', requestId => $id, )->retain;

    } elsif( grep { $request->{url} =~ /$_/ } @{ $self->blacklist }) {
        #warn "Whitelisted URL $request->{url}";
        $mech->target->send_message('Fetch.failRequest', requestId => $id, errorReason => 'AddressUnreachable' )->retain;

    } else {

        my $action;
        if( $self->default eq 'continueRequest' ) {
            $mech->target->send_message('Fetch.continueRequest', requestId => $id, )->retain;
            $action = 'continue';
        } else {
            $mech->target->send_message('Fetch.failRequest', requestId => $id, errorReason => 'AddressUnreachable' );
            $action = 'fail';
        };
        if( my $cb = $self->on_default ) {
            local $@;
            my $ok = eval {
                $cb->($request->{url}, $action);
                1;
            };
            warn $@ if !$ok;
        };
    };
};

=head2 C<< ->enable >>

  $bl->enable( $mech );

Attaches the blacklist to a WWW::Mechanize::Chrome object.

=cut

sub enable( $self, $mech ) {
    $self->_mech( $mech );
    $self->_mech->target->send_message('Fetch.enable');
    my $request_listener = $mech->add_listener('Fetch.requestPaused', sub {
        $self->on_requestPaused( @_ );
    });
    $self->_request_listener( $request_listener );
};

=head2 C<< ->enable >>

  $bl->disable( $mech );

Removes the blacklist to a WWW::Mechanize::Chrome object.

=cut

sub disable( $self ) {
    $self->request_listener(undef);
    $self->_mech->target->send_message('Fetch.disable');
    $self->_mech(undef);
};

1;

__END__

=head1 REPOSITORY

The public repository of this module is
L<https://github.com/Corion/www-mechanize-chrome>.

=head1 SUPPORT

The public support forum of this module is L<https://perlmonks.org/>.

=head1 TALKS

I've given a German talk at GPW 2017, see L<http://act.yapc.eu/gpw2017/talk/7027>
and L<https://corion.net/talks> for the slides.

At The Perl Conference 2017 in Amsterdam, I also presented a talk, see
L<http://act.perlconference.org/tpc-2017-amsterdam/talk/7022>.
The slides for the English presentation at TPCiA 2017 are at
L<https://corion.net/talks/WWW-Mechanize-Chrome/www-mechanize-chrome.en.html>.

=head1 BUG TRACKER

Please report bugs in this module via the Github bug queue at
L<https://github.com/Corion/WWW-Mechanize-Chrome/issues>

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2021 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
