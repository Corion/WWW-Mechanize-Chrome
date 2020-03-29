package WWW::Mechanize::Chrome::URLBlacklist;
use Moo 2;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

our $VERSION = '0.46';

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
            qr!\bgoogleadservices\b!,
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

=cut

has 'request_listener' => (
    is => 'rw',
);

has 'whitelist' => (
    is => 'lazy',
    default => sub { [] },
);

has 'blacklist' => (
    is => 'lazy',
    default => sub { [] },
);

has 'default' => (
    is => 'rw',
    default => 'continueRequest',
);

has 'on_default' => (
    is => 'rw',
);

has 'mech' => (
    is => 'rw',
);

sub on_requestPaused( $self, $info ) {
    my $id = $info->{params}->{requestId};
    my $request = $info->{params}->{request};
    my $mech = $self->mech;

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

sub enable( $self, $mech ) {
    $self->mech( $mech );
    $self->mech->target->send_message('Fetch.enable');
    my $request_listener = $mech->add_listener('Fetch.requestPaused', sub {
        $self->on_requestPaused( @_ );
    });
    $self->request_listener( $request_listener );
};

sub disable( $self ) {
    $self->request_listener(undef);
    $self->mech->target->send_message('Fetch.disable');
    $self->mech(undef);
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

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=WWW-Mechanize-Chrome>
or via mail to L<www-mechanize-Chrome-Bugs@rt.cpan.org|mailto:www-mechanize-Chrome-Bugs@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2020 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
