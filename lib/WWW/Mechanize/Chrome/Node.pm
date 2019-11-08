package WWW::Mechanize::Chrome::Node;
use strict;
use Moo 2;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'signatures';

use Scalar::Util 'weaken';

=head1 NAME

WWW::Mechanize::Chrome::Node - represent a Chrome HTML node in Perl

=head1 SYNOPSIS

    (my $node) = $mech->selector('.download');
    print $node->get_attribute('class'); # "download"

=cut

our $VERSION = '0.39';

=head1 MEMBERS

=head2 C<attributes>

The attributes this node has

=cut

has 'attributes' => (
    is => 'lazy',
    default => sub { {} },
);

=head2 C<nodeName>

The (tag) name of this node, with a namespace

=cut

has 'nodeName' => (
    is => 'ro',
);

=head2 C<localName>

The local (tag) name of this node

=cut

has 'localName' => (
    is => 'ro',
);

=head2 C<backendNodeId>

The id of this node within Chrome

=cut

has 'backendNodeId' => (
    is => 'ro',
);

=head2 C<objectId>

Another id of this node within Chrome

=cut

has 'objectId' => (
    is => 'lazy',
    default => sub( $self ) {
        my $obj = $self->driver->send_message('DOM.resolveNode', nodeId => $self->nodeId)->get;
        $obj->{object}->{objectId}
    },
);

=head2 C<driver>

The L<Chrome::DevToolsProtocol::Transport> instance used to communicate
with Chrome

=cut

has 'driver' => (
    is => 'ro',
);

# The generation from when our ->nodeId was valid
has '_generation' => (
    is => 'rw',
);

=head2 C<mech>

A weak reference to the L<WWW::Mechanize::Chrome> instance used to communicate
with Chrome.

=cut

has 'mech' => (
    is => 'ro',
    weak_ref => 1,
);

=head1 METHODS

=cut

sub _fetchNodeId($self) {
    $self->driver->send_message('DOM.requestNode', objectId => $self->objectId)->then(sub($d) {
        Future->done( 0+$d->{nodeId} );
    });
}

sub _nodeId($self) {
    my $nid = $self->{nodeId};
    my $generation = $self->mech->_generation;
    if( !$nid or ( $self->_generation and $self->_generation != $generation )) {
        # Re-resolve, and hopefully we still have our objectId
        $nid = $self->_fetchNodeId();
        $self->_generation( $generation );
    } else {
        $nid = Future->done( 0+$nid );
    }
    $nid;
}

=head2 C<< ->nodeId >>

  print $node->nodeId();

Lazily fetches the node id of this node

=cut

sub nodeId($self) {
    $self->_nodeId()->get;
}

=head2 C<< ->get_attribute >>

  print $node->get_attribute('outerHTML');

Fetches the attribute of the node from Chrome

=cut

sub get_attribute( $self, $attribute ) {
    my $s = $self;
    weaken $s;
    if( $attribute eq 'innerText' ) {
        my $nid = $self->_nodeId();
        my $html = $nid->then(sub( $nodeId ) {
            $self->driver->send_message('DOM.getOuterHTML', nodeId => 0+$nodeId )
        })->get()->{outerHTML};

        # Strip first and last tag in a not so elegant way
        $html =~ s!\A<[^>]+>!!;
        $html =~ s!<[^>]+>\z!!;
        return $html

    } elsif( $attribute eq 'innerHTML' ) {
        my $nid = $self->_nodeId();
        my $html = $nid->then(sub( $nodeId ) {
            $self->driver->send_message('DOM.getOuterHTML', nodeId => 0+$nodeId )
        })->get()->{outerHTML};

        # Strip first and last tag in a not so elegant way
        $html =~ s!\A<[^>]+>!!;
        $html =~ s!<[^>]+>\z!!;
        return $html

    } elsif( $attribute eq 'outerHTML' ) {
        my $nid = $self->_nodeId();
        my $html = $nid->then(sub( $nodeId ) {
            $self->driver->send_message('DOM.getOuterHTML', nodeId => 0+$nodeId )
        })->get()->{outerHTML};

        return $html
    } else {
        return $self->attributes->{ $attribute }
    }
}

=head2 C<< ->set_attribute >>

  $node->set_attribute('href' => 'https://example.com');

Sets or creates an attribute of a node. To remove an attribute,
pass in the attribute value as C<undef>.

Note that this invalidates the C<nodeId> of every node so you may or may not
need to refetch all other nodes or receive stale values.

=cut

sub set_attribute_future( $self, $attribute, $value ) {
    my $s = $self;
    weaken $s;
    my $r;
    if( defined $value ) {
        $r = $self->_nodeId()
           ->then(sub( $nodeId ) {
            $self->driver->send_message(
                'DOM.setAttributeValue',
                name => $attribute,
                value => $value,
                nodeId => 0+$nodeId
            )
        })

    } else {
        $r = $self->_nodeId()
           ->then(sub( $nodeId ) {
            $self->driver->send_message('DOM.removeAttribute',
                name => $attribute,
                nodeId => 0+$nodeId
            )
        })
    }
    return $r
}

sub set_attribute( $self, $attribute, $value ) {
    $self->set_attribute_future( $attribute, $value )->get
}

=head2 C<< ->get_tag_name >>

  print $node->get_tag_name();

Fetches the tag name of this node

=cut

sub get_tag_name( $self ) {
    my $tag = $self->nodeName;
    $tag =~ s!\..*!!; # strip away the eventual classname
    $tag
}

=head2 C<< ->get_text >>

  print $node->get_text();

Returns the text of the node and the contained child nodes.

=cut

sub get_text( $self ) {
    $self->get_attribute('innerText')
}

=head2 C<< ->set_text >>

  $node->set_text("Hello World");

Sets the text of the node and the contained child nodes.

=cut

sub set_text_future( $self, $value ) {
    my $s = $self;
    weaken $s;
    my $nid = $self->_nodeId();
    $nid->then(sub( $nodeId ) {
        $self->driver->send_message('DOM.setNodeValue', nodeId => 0+$nodeId, value => $value )
    });
}

sub set_text( $self, $value ) {
    $self->set_text_future->get()
}

1;

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

Copyright 2010-2019 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
