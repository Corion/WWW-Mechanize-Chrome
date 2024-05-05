package Chrome::Heapdump 0.01;
use 5.020;
use Moo 2;
use Carp 'croak';

use experimental 'signatures';
use JSON::XS 'decode_json';
use File::Temp 'tempfile';

has 'data' => ( is => 'ro' );

has 'node_field_index' => (
    is => 'ro',
    default => sub { {} },
);

has 'edge_field_index' => (
    is => 'ro',
    default => sub { {} },
);

has 'node_size' => (
    is => 'ro',
);

has 'edge_size' => (
    is => 'ro',
);

has 'dbh' => (
    is => 'ro',
);

sub edges( $self ) { $self->data->{edges} }
sub nodes( $self ) { $self->data->{nodes} }
sub strings( $self ) { $self->data->{strings} }

sub from_string( $package, $str ) {
    my $self = $package->new(data => decode_json( $str ));

    $self->_create_dbh();

    return $self
}

around BUILDARGS => sub( $orig, $class, %args ) {
    my %basic = $class->_init_basic_heap( $args{ data })->%*;

    $args{ $_ } = $basic{ $_ } for keys %basic;

    return $class->$orig( \%args );
};

# This should be in BUILDARGS I guess
sub _init_basic_heap( $class, $heap ) {
    my %res;

    $res{node_size} = scalar @{ $heap->{snapshot}->{meta}->{node_fields} };
    $res{edge_size} = scalar @{ $heap->{snapshot}->{meta}->{edge_fields} };

    # -> test
    #say "Node size: $node_size";
    #say "Edge size: $edge_size";

    my $f = $heap->{snapshot}->{meta}->{node_fields};
    $res{ node_field_index } = +{ map {
            $f->[$_] => $_
        } 0..$#$f
    };

    $f = $heap->{snapshot}->{meta}->{edge_fields};
    $res{ edge_field_index } = +{ map {
            $f->[$_] => $_
        } 0..$#$f
    };

    return \%res
};

sub _create_dbh( $self, $heap = $self->data ) {
    # Now, "load" the nodes and edges
    # We convert everything to a hash first, while we could instead keep all
    # the things as separate arrays. Ah well ...
    my $edge_offset = 0;
    our $node = [map {
        my $n = $self->full_node($_);
        $n->{edge_offset} = $edge_offset;
        $edge_offset += $self->get_edge_count( $_ );
        $n
    } 0..$heap->{snapshot}->{node_count}-1];
    #say $node->[0]->{id};
    our $edge = [map { $self->full_edge($_) } 0..$heap->{snapshot}->{edge_count}-1];

    # Create a temporary database, but on disk so indices actually work
    my ($fh, $dbname) = tempfile;
    close $fh;
    my $dbh = DBI->connect('dbi:SQLite:dbname='.$dbname, undef, undef, { RaiseError => 1, PrintError => 0 });
    $self->{dbh} = $dbh;

    $dbh->sqlite_create_module(perl => "DBD::SQLite::VirtualTable::PerlData");

    my $node_cols = join ",", @{ $heap->{snapshot}->{meta}->{node_fields}};
    my $edge_cols = join ",", @{ $heap->{snapshot}->{meta}->{edge_fields}};
    my $package = __PACKAGE__;

    $dbh->do(<<SQL);
    CREATE VIRTUAL TABLE node_mem USING perl(_idx, edge_offset, $node_cols,
                                        hashrefs="$package\::node");
SQL
    $dbh->do(<<SQL);
    CREATE VIRTUAL TABLE edge_mem USING perl(_idx, _to_node_idx, $edge_cols,
                                        hashrefs="$package\::edge");
SQL

    $dbh->do(<<SQL);
        create table node as select * from node_mem
SQL
    $dbh->do(<<SQL);
        create table edge as select * from edge_mem
SQL


# Not allowed for virtual tables, which is why we use the on disk variant
    $dbh->do(<<SQL);
    CREATE index by_name_index on node (name, _idx, id);
    CREATE unique index by_idx_index on node (_idx, name, type, edge_count);
    CREATE unique index by_id_index on node (id, _idx, name, type, edge_count);
SQL
    $dbh->do(<<SQL);
    CREATE unique index by_index on edge (_idx, _to_node_idx, name_or_index);
SQL

}

sub full_node( $self,  $idx ) {
    my $heap = $self->data;
    return +{
        _idx => $idx,
        map {
            $_ => $self->get_node_field( $idx, $_ )
        } @{ $heap->{snapshot}->{meta}->{node_fields} }
    }
}

sub get_node_field($self, $idx, $fieldname) {
    my $heap = $self->data;
    croak "Invalid node field name '$fieldname'. Known fields are " . join ", ", values $self->node_field_index->%*
        unless exists $self->{node_field_index}->{ $fieldname };
    if( $idx > $heap->{snapshot}->{node_count}) {
        croak "Invalid node index '$idx'";
    };

    # Depending on the type of the field, this can be either a string id
    # or the numeric value to use...
    my $fi = $self->{node_field_index}->{ $fieldname };
    my $val = $heap->{nodes}->[$idx*$self->{node_size}+$fi];
    if( ! defined $val ) {
        warn "Node $idx.$fieldname: undefined"; # $idx*$node_size+$fi
    }

    my $ft = $heap->{snapshot}->{meta}->{node_types}->[$fi];
    if( ref $ft eq 'ARRAY' ) {
        $val = $ft->[$val]
    } elsif( $ft eq 'number' ) {
        # we use the value as-is
    } elsif( $ft eq 'string' ) {
        $val = $heap->{strings}->[$val]
        #croak "String-fetching for node types not implemented";
    } else {
        croak "Unknown node field type '$ft' for '$fieldname'";
    }

    return $val;
}

# Returns the edge_count field of a node
sub get_edge_count( $self, $idx ) {
    return $self->get_node_field( $idx, 'edge_count' )
}

sub full_edge( $self, $idx ) {
    my $heap = $self->data;
    my $res = +{
        _idx => $idx,
        map {
            $_ => $self->get_edge_field( $idx, $_ )
        } @{ $heap->{snapshot}->{meta}->{edge_fields} }
    };

    if( $res->{type} eq 'element'
        or $res->{type} eq 'hidden' ) {
        # We don't want the string but the number as value:
        $res->{index} = $res->{name_or_index} = $self->get_edge_field( $idx, 'name_or_index', 1 );
        $res->{name} = undef;
    } else {
        $res->{name} = $res->{name_or_index};
        $res->{index} = undef;
    }

    $res->{_to_node_idx} = $res->{to_node} / @{ $heap->{snapshot}->{meta}->{node_fields} };
    $res;
}

sub get_edge_field($self, $idx, $fieldname, $as_index=undef) {
    croak "Invalid edge field name '$fieldname'"
        unless exists $self->edge_field_index->{ $fieldname };
    croak "Invalid index"
        unless defined $idx;
    my $heap = $self->data;

    if( $idx >= $heap->{snapshot}->{edge_count} ) {
        croak "Invalid edge index $idx, maximum is $heap->{snapshot}->{edge_count}";
    }

    # Depending on the type of the field, this can be either a string id
    # or the numeric value to use...
    my $fi = $self->edge_field_index->{ $fieldname };
    my $val = ($self->edge_at_index( $idx ))[$fi];

    my $ft = $heap->{snapshot}->{meta}->{edge_types}->[$fi];
    if( ref $ft eq 'ARRAY' ) {
        $val = $ft->[$val]
    } elsif( $ft eq 'number' ) {
        # we use the value as-is
    } elsif( $ft eq 'node' ) {
        # we use the value as-is
    } elsif( $ft eq 'string' ) {
        $val = $heap->{strings}->[$val]
    } elsif( $ft eq 'string_or_number' ) {
        if( !$as_index ) {
            $val = $heap->{strings}->[$val]
        }
    } else {
        croak "Unknown edge field type '$ft' for '$fieldname'";
    }
    return $val;
}

sub edge_at_index( $self, $idx ) {
    my $ofs = $idx * $self->{edge_size};
    # Maybe return an arrayref here, later?
    my $heap = $self->data;
    return @{ $heap->{edges} }[ $ofs .. $ofs+($self->edge_size-1) ];
}

sub node_at_index( $self, $heap, $idx ) {
    my $ofs = $idx * $self->node_size;
    @{ $heap->{nodes} }[ $ofs .. $ofs+($self->node_size-1) ];
}

sub node_by_id( $self, $node_id ) {
    croak "Node id cannot be undef"
        unless defined $node_id;
    # Maybe some kind of caching here, as well, or gradually building
    # a hash out of/into the structure?!
    my $heap = $self->data;
    for my $idx ( 0..$heap->{snapshot}->{node_count}-1 ) {
        my $id = $self->get_node_field($idx, 'id');
        #my $name = get_node_field($heap, $idx, 'name');
        #my $type = get_node_field($heap, $idx, 'type');
        #warn "$node_id:$idx: $id $name [$type]";
        if( $id == $node_id ) {
            return $idx
        };
    }
    croak "Unknown node id $node_id";
}

sub edge( $self, $heap, $idx ) {
    my @vals = $self->edge_at_index( $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{edge_fields}, \@vals
    }
}

sub node( $self, $heap, $idx ) {
    my @vals = node_at_index( $self, $heap, $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{node_fields}, \@vals
    }
}

# Returns the node index of the target node
sub get_edge_target( $self, $idx ) {
    croak "Invalid index"
        unless defined $idx;
    my $v = $self->get_edge_field( $idx, 'to_node' );
    return $v / $self->node_size
}

=head2 C<< ->find_string_exact >>

Returns information on nodes containing the exact string

=cut

sub find_string_exact($self, $value, $path='/strings') {
    my @res;
    $self->iterate($self->strings, sub($item, $path) {
        if( ref $item eq 'HASH' ) {
            if( grep { defined $_ and $_ eq $value } values %$item ) {
                my @keys = grep { defined $item->{$_} and $item->{$_} eq $value } keys %$item;
                for my $k (sort @keys) {
                    push @res, { path => "$path/$k", value => $item->{k}, index => $k };
                };
            };
        } elsif( ref $item eq 'ARRAY' ) {
            if( grep { defined $_ and $_ eq $value } @$item ) {
                my @indices = grep { defined $item->[$_] and $item->[$_] eq $value } 0..$#$item;
                push @res, map +{ path => "$path\[$_]", value => $item->[$_], index => $_ }, @indices;
            };
        }
    });
    return @res
}

# Now, search the heap for an object containing our magic strings:
#
my %seen;
sub iterate($self, $data, $visit, $path='', $vis=$path) {
    # Check if we find the hash keys:
    if( ! $seen{ $vis }++ ) {
        print "$vis\n";
    };
    $visit->($data, $path);
    if( ref $data eq 'HASH' ) {
        for my $key (sort keys %$data) {
            my $val = $data->{$key};
            if( ref $val) {
                my $sub = "$path/$key";
                my $subvis = $sub;
                $self->iterate( $val, $visit, $sub, $subvis );
            }
        }
    } elsif( ref $data eq 'ARRAY' ) {
        for my $i (0..$#$data) {
            my $val = $data->[$i];
            if( ref $val) {
                my $sub = "$path\[$i\]";
                my $subvis = "$path\[.\]";
                $self->iterate( $val, $visit, $sub, $subvis );
            }
        }
    };
}

1;
