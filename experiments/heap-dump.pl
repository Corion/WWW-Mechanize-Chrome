#!perl
use strict;
use warnings;
use Filter::signatures;
no warnings 'experimental::signatures';
use feature 'say';
use File::Temp 'tempdir';
use Carp 'croak';

use WWW::Mechanize::Chrome;
use JSON;
use Log::Log4perl ':easy';
use List::Util 'mesh';
Log::Log4perl->easy_init($WARN);

my $mech = WWW::Mechanize::Chrome->new(
    data_directory => tempdir( CLEANUP => 1 ),
);
$mech->target->send_message('HeapProfiler.enable')->get;

#$mech->get('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
#$mech->get('https://www.youtube.com/embed/dQw4w9WgXcQ');

# Let's start with something simpler
$mech->get_local('heap-test-01.html');
my $chunk;
my $done = $mech->target->future;
my $collector = $mech->target->add_listener( 'HeapProfiler.addHeapSnapshotChunk', sub($message) {
    $chunk .= $message->{params}->{chunk};

    # We know that we're done if we receive a chunk with "]}" ?!
    if( $chunk =~ /\]\}$/ ) {
        $done->done($chunk);
    };
});

my $info =
$mech->target->send_message(
    'HeapProfiler.takeHeapSnapshot',
    captureNumericValue => JSON::true,
    treatGlobalObjectsAsRoots => JSON::true,
)->get;

#$mech->sleep(30);
my $heapdump = $done->get;
my $heap = decode_json($heapdump);

#use Data::Dumper;
#print Dumper $heap->{strings};

# Now, search the heap for an object containing our magic strings:
#
my %seen;
sub iterate($heap, $visit, $path='', $vis=$path) {
    # Check if we find the hash keys:
    if( ! $seen{ $vis }++ ) {
        print "$vis\n";
    };
    $visit->($heap, $path);
    if( ref $heap eq 'HASH' ) {
        for my $key (sort keys %$heap) {
            my $val = $heap->{$key};
            if( ref $val) {
                my $sub = "$path/$key";
                my $subvis = $sub;
                iterate( $val, $visit, $sub, $subvis );
            }
        }
    } elsif( ref $heap eq 'ARRAY' ) {
        for my $i (0..$#$heap) {
            my $val = $heap->[$i];
            if( ref $val) {
                my $sub = "$path\[$i\]";
                my $subvis = "$path\[.\]";
                iterate( $val, $visit, $sub, $subvis );
            }
        }
    };
}

sub find_string($heap, $value, $path='/strings') {
    my @res;
    iterate($heap->{strings}, sub($item, $path) {
        if( ref $item eq 'HASH' ) {
            if( grep { defined $_ and $_ =~ /$value/ } values %$item ) {
                my @keys = grep { defined $item->{$_} and $item->{$_} =~ $value } keys %$item;
                for my $k (sort @keys) {
                    push @res, { path => "$path/$k", value => $item->{k} };
                };
            };
        } elsif( ref $item eq 'ARRAY' ) {
            if( grep { defined $_ and $_ =~ /$value/ } @$item ) {
                my @indices = grep { defined $item->[$_] and $item->[$_] =~ $value } 0..$#$item;
                push @res, map +{ path => "$path\[$_]", value => $item->[$_] }, @indices;
            };
        }
    });
    @res
}

sub find_string_exact($heap, $value, $path='/strings') {
    my @res;
    iterate($heap->{strings}, sub($item, $path) {
        if( ref $item eq 'HASH' ) {
            if( grep { defined $_ and $_ =~ /$value/ } values %$item ) {
                my @keys = grep { defined $item->{$_} and $item->{$_} eq $value } keys %$item;
                for my $k (sort @keys) {
                    push @res, { path => "$path/$k", value => $item->{k} };
                };
            };
        } elsif( ref $item eq 'ARRAY' ) {
            if( grep { defined $_ and $_ =~ /$value/ } @$item ) {
                my @indices = grep { defined $item->[$_] and $item->[$_] eq $value } 0..$#$item;
                push @res, map +{ path => "$path\[$_]", value => $item->[$_] }, @indices;
            };
        }
    });
    @res
}

use Data::Dumper;
#my @usage = find_string_exact($heap,'Rick Astley');
my @usage = find_string_exact($heap,'bar');
#my @usage = find_string($heap,'bar');
#my @usage = find_string($heap,'foo');
#my @usage = find_string($heap,'baz');
print Dumper \@usage;
#print Dumper $heap->{strings};

$usage[0]->{path} =~ /\[(\d+)\]/ or die "Weirdo path: '$usage[0]->{path}'";
my $idx = $1;

# strings <- edge
# strings <- node

say "Edge:", $heap->{edges}->[$idx];
say "Node:", $heap->{nodes}->[$idx];

sub field_value( $heap, $type, $name, $values ) {
    my $f = $heap->{snapshot}->{meta}->{"${type}_fields"};
    (my $idx) = grep { $f->[$_] eq $name } @$f;
    die "Unknown field name '$name'" if ! defined $idx;

    my $field_type = $heap->{snapshot}->{meta}->{"$type\_types"}->{$idx};
    my $field_val  = $values->{$idx};

    if( ref $field_type and ref $field_type eq 'ARRAY' ) {
    } elsif( $field_type eq 'string' ) {
        return $heap->{strings}->[$field_val];
    } elsif( $field_type eq 'number' ) {
    } else {
        croak "Unknown field type '$field_type'";
    }

}

## Size of a node/edge
# These are stored as flat arrays and the names of the keys are stored
# in snapshot/meta/{node,edge}_fields
# each node has (currently) 7 fields
# each edge has (currently) 3 fields
#print Dumper $heap->{snapshot}->{meta}->{node_fields};
#print Dumper $heap->{snapshot}->{meta}->{edge_fields};
my $node_size = scalar @{ $heap->{snapshot}->{meta}->{node_fields} };
my $edge_size = scalar @{ $heap->{snapshot}->{meta}->{edge_fields} };
say "Node size: $node_size";
say "Edge size: $edge_size";

say Dumper $heap->{snapshot}->{meta}->{edge_types};

sub edge_at_index( $heap, $idx ) {
    my $ofs = $idx * $edge_size;
    # Maybe return an arrayref here, later?
    return @{ $heap->{edges} }[ $ofs .. $ofs+($edge_size-1) ];
}

sub node_at_index( $heap, $idx ) {
    my $ofs = $idx * $node_size;
    @{ $heap->{nodes} }[ $ofs .. $ofs+($node_size-1) ];
}

sub edge( $heap, $idx ) {
    my @vals = edge_at_index( $heap, $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{edge_fields}, \@vals
    }
}

sub node( $heap, $idx ) {
    my @vals = node_at_index( $heap, $idx );
    +{
        mesh $heap->{snapshot}->{meta}->{node_fields}, \@vals
    }
}

#print field_value($heap, 'node', ,
print Dumper [ edge( $heap, $idx )];
print Dumper [ node( $heap, $idx )];

#print Dumper $heap->{snapshot}->{meta}->{node_types};

#find_value($heap,'Astley');
#find_value($heap,'dQw4w9WgXcQ');
