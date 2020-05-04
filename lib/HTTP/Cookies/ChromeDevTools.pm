package HTTP::Cookies::ChromeDevTools;
use strict;
use Carp qw[croak];

our $VERSION = '0.51';
our @CARP_NOT;

use Moo 2;
use JSON;
use Filter::signatures;
use feature 'signatures';
no warnings 'experimental::signatures';

extends 'HTTP::Cookies';

=head1 NAME

HTTP::Cookies::ChromeDevTools - retrieve cookies from a live Chrome instance

=head1 SYNOPSIS

  use HTTP::Cookies::ChromeDevTools;
  my $cookie_jar = HTTP::Cookies::ChromeDevTools->new();
  # use just like HTTP::Cookies

=head1 DESCRIPTION

This package overrides the load() and save() methods of HTTP::Cookies
so it can work with a live Chrome instance.

=head1 Reusing an existing connection

If you already have an existing connection to Chrome
that you want to reuse, just pass the L<Chrome::DevToolsProtocol>
instance to the cookie jar constructor in the C<driver> parameter:

  my $cookie_jar = HTTP::Cookies::ChromeDevTools->new(
      driver => $driver
  );

=cut

has 'transport' => (
    is => 'lazy',
    default => sub {
        $ENV{ WWW_MECHANIZE_CHROME_TRANSPORT }
    },
);

has 'driver' => (
    is => 'lazy',
    default => sub {
        my( $self ) = @_;

        # Connect to it
        Chrome::DevToolsProtocol->new(
            'port' => $self->{ port },
            host => $self->{ host },
            auto_close => 0,
            error_handler => sub {
                #warn ref$_[0];
                #warn "<<@CARP_NOT>>";
                #warn ((caller($_))[0,1,2])
                #    for 1..4;
                local @CARP_NOT = (@CARP_NOT, ref $_[0],'Try::Tiny');
                # Reraise the error
                croak $_[1]
            },
            transport => $self->transport,
            log => $self->{ log },
        )
    },
);

has '_loading' => (
    is => 'rw',
    default => 0,
);

=head2 C<< ->load( $file, %options ) >>

    $jar->load( undef, driver => $driver );

Loads the cookies from the Chrome instance. Passing in a filename to load
cookies from is currently unsupported.
=cut

sub load($self, $file=undef, %options) {
    my $driver = $options{ driver } || $self->driver;
    my $cookies = $driver->send_message('Network.getAllCookies')->get();
    $cookies = $cookies->{cookies};
    $self->clear();
    local $self->{_loading} = 1;
    for my $c (@$cookies) {
        $self->set_cookie(
            1,
            $c->{name},
            $c->{value},
            $c->{path},
            $c->{domain},
            undef, # Chrome doesn't support port numbers?!
            undef,
            $c->{httpOnly},
            $c->{secure},
            $c->{expires},
            #$c->{session},
        );
    };
    if( $file ) {
        my $jar = HTTP::Cookies->new( file => $file );
        $self->load_jar( $jar );
    };
}

=head2 C<< ->load_jar( $jar, %options ) >>

    $jar->load( $jar, replace => 1;

Imports the cookies from another cookie jar into Chrome.

B<replace> will clear out the cookie jar before loading the fresh cookies.

=cut

sub load_jar($self, $jar, %options) {
    my $driver = $options{ driver } || $self->driver;

    if( $options{ replace }) {
        $driver->send_message('Network.clearBrowserCookies')->get();
        $self->clear();
    };

    local $self->{_loading} = 0;
    $jar->scan( sub(@c) {
        my $c = {};
        @{$c}{qw(version name value path domain port path_spec secure expires discard hash)} = @c;
        $self->set_cookie(
            1,
            $c->{name},
            $c->{value},
            $c->{path},
            $c->{domain},
            undef, # Chrome doesn't support port numbers?!
            undef,
            $c->{httpOnly},
            $c->{secure},
            $c->{expires},
            #$c->{session},
        );
    });
}

sub set_cookie($self, $version, $key, $val, $path, $domain, $port, $path_spec, $secure, $maxage, $discard) {

    # We've just read from Chrome, so just update our local variables
    $self->SUPER::set_cookie( $version, $key, $val, $path, $domain, $port, $path_spec, $secure, $maxage, $discard );

    if( ! $self->_loading ) {
        # Update Chrome
        $maxage += time();
        $self
          ->set_cookie_in_chrome($version, $key, $val, $path, $domain, $port, $path_spec, $secure, $maxage, $discard)
          ->get();
    };
};

sub set_cookie_in_chrome($self, $version, $key, $val, $path, $domain, $port, $path_spec, $secure, $maxage, $discard) {
    # Update Chrome
    my $driver = $self->driver;

    $maxage += time();

    $driver->send_message('Network.setCookie',
        name     => $key,
        value    => $val,
        path     => $path,
        domain   => $domain,
        httpOnly => JSON::false,
        expires  => $maxage,
        secure   => ($secure ? JSON::true : JSON::false),
    );
};

sub save {
    croak 'save is not yet implemented'
}

1;

__END__

=head1 SEE ALSO

L<HTTP::Cookies> - the interface used

L<HTTP::Cookies::Chrome> - offline access to Chrome cookies

=head1 REPOSITORY

The public repository of this module is
L<http://github.com/Corion/www-mechanize-chrome>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2009-2020 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
