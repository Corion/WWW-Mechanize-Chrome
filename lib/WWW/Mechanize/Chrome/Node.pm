package WWW::Mechanize::Chrome::Node;
use strict;
use 5.020; # __SUB__, signatures
use Moo 2;
no warnings 'experimental::signatures';
use feature 'signatures';
use Carp qw( croak );
use JSON;

use Scalar::Util 'weaken';

=head1 NAME

WWW::Mechanize::Chrome::Node - represent a Chrome HTML node in Perl

=head1 SYNOPSIS

    (my $node) = $mech->selector('.download');
    print $node->get_attribute('class'); # "download"

=cut

our $VERSION = '0.77';

=head1 MEMBERS

=head2 C<attributes>

The attributes this node has

=cut
has 'attributes' => (
    is => 'rw',
    default => sub { {} },
    coerce => sub {
        my $v = shift;
        if( ref $v eq 'ARRAY' ) {
            return { @$v };
        };
        return $v
    },
);

=head2 C<nodeName>

The (tag) name of this node, with a namespace

=cut

has 'nodeName' => (
    is => 'ro',
);

=head2 C<nodeId>

The nodeId of this node

=cut

has 'nodeId' => (
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

=head2 C<cachedNodeId>

The cached id of this node for this session

=cut

has 'cachedNodeId' => (
    is => 'rw',
);

=head2 C<objectId>

Another id of this node within Chrome

=cut

has 'objectId' => (
    is => 'rw',
);

around objectId => sub {
    my $orig = shift;
    my $self = shift;
    if( @_ ) {
        return $self->$orig(@_);
    }
    return $self->{objectId} // $self->objectId_future->get;
};

sub objectId_future($self) {
    return $self->_fetchObjectId;
}

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

=head1 CONSTRUCTORS


=head2 C<< fetchNode >>

  WWW::Mechanize::Chrome->fetchNode(
      nodeId => $nodeId,
      driver => $mech->driver,
  )->get()

Returns a L<Future> that returns a populated node.

=cut

sub fetchNode( $class, %options ) {
    my $driver = delete $options{ driver }
        or croak "Need a valid driver for communication";
    weaken $driver;
    defined(my $nodeId = delete $options{ nodeId })
        or croak "Need a valid nodeId for requesting";
    my $body = delete $options{ body };
    my $attributes = delete $options{ attributes };

    if( $body ) {
        $body = Future->done( $body );
    } else {
        my %info;
        $body = $driver->send_message( 'DOM.resolveNode', nodeId => 0+$nodeId )
        ->then( sub( $info ) {
            %info = %{$info->{object}};
            $driver->send_message( 'DOM.requestNode', objectId => $info{objectId} )
        })->then(sub( $info ) {
            %info = (%info, %$info);
            $driver->send_message( 'DOM.describeNode', objectId => $info{objectId} )
        })->then(sub( $info ) {
            %info = (%info, %{$info->{node}}, nodeId => 0+$nodeId);

            Future->done( \%info );
        })->catch( sub(@error) {
            warn "Couldn't resolve node $nodeId!";
            # use Data::Dumper; warn Dumper \@error;
            return Future->fail( @error );
        })
    };
    if( $attributes ) {
        $attributes = Future->done( $attributes )
    } else {
        $attributes = $driver->send_message( 'DOM.getAttributes', nodeId => 0+$nodeId );
    };

    return Future->wait_all( $body, $attributes )->then( sub( $body, $attributes ) {
        $body = $body->get;
        my $attr = $attributes->get;
        $attributes = $attr->{attributes};
        my $nodeName = $body->{description};
        $nodeName =~ s!#.*!!;
        #warn "Backend for $nodeId is $attr->{ backendNodeId }";
        #use Data::Dumper;
        #warn Dumper $attr;
        #warn Dumper $body;
        #die unless $attr->{backendNodeId};
        my $node = {
            cachedNodeId => $nodeId,
            objectId => $body->{ objectId },
            backendNodeId => $body->{backendNodeId} || $attr->{ backendNodeId },
            nodeId => $nodeId,
            parentId => $body->{ parentId },
            attributes => {
                @{ $attributes },
            },
            nodeName => $nodeName,
            #driver => $driver,
            #mech => $s,
            #_generation => $s->_generation,
        };
        $node->{driver} = $driver;
        my $n = $class->new( $node );

        # Fetch additional data into the object
        #return $n->_nodeId()->then(sub {
        #    unless( $n->backendNodeId ) {
        #        warn Dumper [ $body, $attributes ];
        #        die;
        #    };
        #});
        return Future->done( $n );
    })->catch(sub {
        warn "@_";
        warn "Node $nodeId has gone away in the meantime, could not resolve";
        return Future->done( $class->new( {} ) );
    });
}

sub _fetchObjectId( $self ) {
    #warn "Realizing objectId";
    if( $self->{objectId}) {
        return Future->done( $self->{objectId} )
    } else {
        my $s = $self;
        weaken $s;
        my $nodeId = $self->nodeId // $self->cachedNodeId;
        if( ! $nodeId ) {
            return Future->fail("Cannot resolve objectId without nodeId");
        }
        $self->{_fetchObjectId} //= $s->driver->send_message('DOM.resolveNode', nodeId => 0+$nodeId )
        ->then(sub($obj) {
            $s->{objectId} = $obj->{object}->{objectId};
            return Future->done($s->{objectId});
        })->on_ready(sub {
            if( $s ) {
                delete $s->{_fetchObjectId};
            }
        });
        return $self->{_fetchObjectId};
    }
}

sub _fetchNodeId($self) {
    my $s = $self;
    return $self->_fetchObjectId->then(sub( $objectId ) {
        $s->driver->send_message('DOM.requestNode', objectId => $objectId)
    })->then(sub($d) {
        if( ! exists $d->{node} ) {
            # Ugh - that node has gone away before we could request it ...
            return Future->done( $d->{nodeId} );
        } else {
            $s->{backendNodeId} = 0+$d->{node}->{backendNodeId};
            $s->{nodeId} = 0+$d->{node}->{nodeId} // 0+$s->{nodeId}; # keep old one ...
            $s->cachedNodeId( 0+$d->{node}->{nodeId} // 0+$s->{nodeId} );
            return Future->done( $s->{nodeId} );
        };
    });
}

sub _nodeId($self) {
    my $nid;
    if( my $mech = $self->mech ) {
        my $generation = $mech->_generation;
        if( !$self->_generation or $self->_generation != $generation ) {
            # Re-resolve, and hopefully we still have our objectId
            $nid = $self->_fetchNodeId();
            $self->_generation( $generation );
        }
    }
    
    if( ! $nid ) {
        my $id = $self->cachedNodeId // $self->nodeId;
        $nid = Future->done( 0+($id // 0) );
    }
    return $nid;
}
#
#=head2 C<< ->nodeId >>
#
#  print $node->nodeId();
#
#Lazily fetches the node id of this node. Use C<< ->_nodeId >> for a version
#that returns a Future.
#
#=cut
#
#sub nodeId($self) {
#    $self->_nodeId()->get;
#}

=head1 METHODS

=cut

=head2 C<< ->get_attribute >>

  print $node->get_attribute('outerHTML');

Fetches the attribute of the node from Chrome

  print $node->get_attribute('href', live => 1);

Force a live query of the attribute to Chrome. If the attribute was declared
on the node, this overrides the stored value and queries Chrome again for
the current value of the attribute.

=cut

sub _false_to_undef( $val ) {
    if( ref $val and ref $val eq 'JSON::PP::Boolean' ) {
        $val = $val ? $val : undef;
    }
    return $val
}

sub _fetch_attribute_eval( $self, $attribute ) {
    my $s = $self;
    return $self->_fetchObjectId
    ->then( sub( $objectId ) {
        $s->driver->send_message('Runtime.callFunctionOn',
            functionDeclaration => '(o,a) => { return o[a] }',
            arguments => [ { objectId => $objectId }, { value => $attribute } ],
            objectId => $objectId,
            returnByValue => JSON::true
        )
    })
    ->then(sub($_res) {
        my $val = $_res->{result}->{value};
        return Future->done( _false_to_undef( $val ))
    });
}

sub _fetch_attribute_attribute( $self, $attribute ) {
    return $self->_nodeId->then(sub($nodeId) {
        $self->driver->send_message('DOM.getAttributes',
            nodeId => 0+$nodeId,
        )
    })
    ->then(sub($_res) {
        my %attr = @{ $_res->{attributes} };
        my $res = $attr{ $attribute };
        return Future->done( _false_to_undef( $res ))
    });
}

sub _fetch_attribute_property( $self, $attribute ) {
    my $s = $self;
    return $self->_fetchObjectId
    ->then( sub( $objectId ) {
    $s->driver->send_message('Runtime.getProperties',
        objectId => $objectId,
        #ownProperties => JSON::true,
        #accessorPropertiesOnly => JSON::true,
        #returnByValue => JSON::true
    )})
    ->then(sub($_res) {
        (my $attr) = grep { $_->{name} eq $attribute } @{ $_res->{result} };
        $attr //= {};
        my $res = $attr->{value}->{value};
        return Future->done( _false_to_undef( $res ))
    });
}

sub _fetch_attribute( $self, $attribute ) {
    my $s = $self;
    return $s->_fetch_attribute_attribute( $attribute )->then(sub ($val) {
        if( ! defined $val) {
            return $s->_fetch_attribute_property( $attribute )->then(sub ($val) {
                if( ! defined $val) {
                    return $s->_fetch_attribute_eval( $attribute )
                } else {
                    return Future->done( $val )
                }
            })
        } else {
                return Future->done( $val )
        }
    });
}

sub get_attribute_future( $self, $attribute, %options ) {
    my $s = $self;

    if( $attribute eq 'innerHTML' ) {
        return $s->get_attribute_future('outerHTML')
        ->then(sub( $html ) {
            # Strip first and last tag in a not so elegant way
            $html =~ s!\A<[^>]+>!!;
            $html =~ s!<[^>]+>\z!!;
            return Future->done( $html )
        });

    } elsif( $attribute eq 'outerHTML' ) {
        return $s->_fetchNodeId()->then(sub( $nodeId ) {
            (my $key) = grep { $s->$_ } (qw(backendNodeId nodeId));
            my $val;

            if( ! $key ) {
                $key = 'nodeId';
                $val = 0+$nodeId;
            } else {
                $val = $s->$key;
            };

            #$s->driver->send_message('DOM.getOuterHTML', nodeId => 0+$nodeId )
            return $s->driver->send_message('DOM.getOuterHTML', $key => $val )
        })->then(sub( $res ) {
            return Future->done( $res->{outerHTML} )
        });

    } else {
        if( ! $options{ live } ) {
            my $attrs = $s->attributes;
            if( exists $attrs->{ $attribute } ) {
                return Future->done( $attrs->{ $attribute } );
            };
        };
        #warn "Fetching '$attribute'";
        return $s->_fetch_attribute($attribute);
    }
}

sub get_attribute( $self, $attribute, %options ) {
    return $self->get_attribute_future( $attribute, %options )->get()
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
        $r = $s->_fetchNodeId()
           ->then(sub( $nodeId ) {
            return $s->driver->send_message(
                'DOM.setAttributeValue',
                name => $attribute,
                value => ''.$value,
                nodeId => 0+$nodeId
            )
        })->then(sub {
            $s->attributes->{ $attribute } = $value;
            return Future->done($s);
        });

    } else {
        $r = $s->_fetchNodeId()
           ->then(sub( $nodeId ) {
            return $s->driver->send_message('DOM.removeAttribute',
                name => $attribute,
                nodeId => 0+$nodeId
            )
        })->then(sub {
            delete $s->attributes->{ $attribute };
            return Future->done($s);
        });
    }
    return $r
}

sub set_attribute( $self, $attribute, $value ) {
    return $self->set_attribute_future( $attribute, $value )->get
}

=head2 C<< ->get_tag_name >>

  print $node->get_tag_name();

Fetches the tag name of this node

=cut

sub get_tag_name_future( $self ) {
    return Future->done( $self->get_tag_name );
}

sub get_tag_name( $self ) {
    my $tag = $self->nodeName // "";
    $tag =~ s!\..*!!; # strip away the eventual classname
    return $tag
}

=head2 C<< ->get_text >>

  print $node->get_text();

Returns the text of the node and the contained child nodes.

=cut

sub get_text_future( $self ) {
    return $self->get_attribute_future('innerText')
}

sub get_text( $self ) {
    return $self->get_text_future->get();
}

=head2 C<< ->set_text >>

  $node->set_text("Hello World");

Sets the text of the node and the contained child nodes.

=cut

sub set_text_future( $self, $value ) {
    my $s = $self;
    return $self->_nodeId()->then(sub( $nodeId ) {
        return $s->driver->send_message('DOM.setNodeValue', nodeId => 0+$nodeId, value => $value )
    });
}

sub set_text( $self, $value ) {
    return $self->set_text_future($value)->get()
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

Please report bugs in this module via the Github bug queue at
L<https://github.com/Corion/WWW-Mechanize-Chrome/issues>

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2010-2024 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
