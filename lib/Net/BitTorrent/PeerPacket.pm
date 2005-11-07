#!/usr/local/bin/perl

package Net::BitTorrent::PeerPacket;

use strict;
use warnings;
use Carp;
use base 'Exporter';

our $VERSION = '1.0';

# Build list of packet names, order is significant, as the index of the type 
# represents it's code in BitTorrent
my( @code_num_to_str, %code_str_to_num );

BEGIN {    @code_num_to_str = qw(
        BT_CHOKE
        BT_UNCHOKE
        BT_INTERESTED
        BT_UNINTERESTED
        BT_HAVE
        BT_BITFIELD
        BT_REQUEST
        BT_PIECE
        BT_CANCEL
    );

    # The array @code_num_to_str serves as a packet code to packet name
    # map.  Flip that into a hash that serves as a name to code map
    %code_str_to_num = 
        map { $code_num_to_str[$_] => $_ } 0 .. $#code_num_to_str;
}

# Turn the hash of name-id pairs into a bunch of constants based on the names
use constant \%code_str_to_num;

# Allow for the export of our build and parse subroutines and bt codes
our @EXPORT_OK = ('bt_build_packet', 'bt_parse_packet', keys %code_str_to_num);

# create an :all tag for subroutines and constants and a :constants tag for
# just the constants
our %EXPORT_TAGS = (
    'all'       => [ @EXPORT_OK ],
    'constants' => [ @code_num_to_str ],
);

# Map build and parse subroutines
my $bt_base_code = 0;
my (%bt_dispatch) = map( { $bt_base_code++ => $_ } 
    {
        build   => sub { return _build_packet( BT_CHOKE ) },
        parse   => { bt_code => BT_CHOKE },
    },
    {
        build   => sub { return _build_packet( BT_UNCHOKE ) },
        parse   => { bt_code => BT_UNCHOKE },
    },
    {
        build   => sub { return _build_packet( BT_INTERESTED ) },
        parse   => { bt_code => BT_INTERESTED },
    },
    {
        build   => sub { return _build_packet( BT_UNINTERESTED ) },
        parse   => { bt_code => BT_UNINTERESTED },
    },
    {
        build   => \&_build_have_packet,
        parse   => \&_parse_have_packet,
    },
    {
        build   => \&_build_bitfield_packet,
        parse   => \&_parse_bitfield_packet,
    },
    {
        build   => \&_build_request_packet,
        parse   => \&_parse_request_packet,
    },
    {
        build   => \&_build_piece_packet,
        parse   => \&_parse_piece_packet,
    },
    {
        build   => \&_build_cancel_packet,
        parse   => \&_parse_cancel_packet,
    },
);

##########################################################################
# P U B L I C    S U B R O U T I N E S
##########################################################################

sub bt_build_packet {

    # hashify arguments
    @_%2 == 0
        or croak("Even number of elements expected, but not received");

    my %args = @_;

    _hash_defines(\%args, 'bt_code');
 
    my $bt_code = $args{bt_code};
    
    # look-up build subroutine
    defined $bt_dispatch{$bt_code}
        or croak("Invalid BT code ($bt_code) found");
    
    my $sub_ref = $bt_dispatch{$bt_code}{build};
    
    # execute the subroutine
    return $sub_ref->(\%args);
}

sub bt_parse_packet {
    my ($packet_ref) = @_;
    
    my ($bt_code) = unpack('x4C', ${$packet_ref});

    defined $bt_dispatch{$bt_code}
        or croak("Invalid BT code ($bt_code) found");

    my $parse_ref = $bt_dispatch{$bt_code}{parse};
   
    # for easy packets, we just get the hash ref back
    return $parse_ref if(ref $parse_ref eq 'HASH');
    
    # execute the subroutine
    return $parse_ref->(\substr(${$packet_ref}, 5));
}

1;

##########################################################################
# P R I V A T E    S U B R O U T I N E S
##########################################################################

#
# _build_have_packet PIECE_INDEX
#     Return a have packet
#
sub _build_have_packet {
    my($args) = @_;

    _hash_defines($args, 'piece_index');

    my $packet_body = pack( 'N', $args->{piece_index} );

    return _build_packet( BT_HAVE, $packet_body );
}

#
# _build_bitfield_packet BITFIELD
#     Return a bitfield packet
#
sub _build_bitfield_packet {
    my($args) = @_;

    _hash_defines($args, 'bitfield_ref');

    return _build_packet( BT_BITFIELD, '', $args->{bitfield_ref} );
}

#
# _build_request_packet PIECE_INDEX BIT_OFFSET BIT_LENGTH
#     Return a request packet
#
sub _build_request_packet {
    my($args) = @_;

    _hash_defines($args, 'piece_index', 'block_offset', 'block_size');

    my $packet_body = pack( 'NNN', 
                            $args->{piece_index}, 
                            $args->{block_offset}, 
                            $args->{block_size} 
                           );

    return _build_packet( BT_REQUEST, $packet_body );
}

#
# _build_piece_packet PIECE_INDEX BIT_OFFSET DATA
#     Return a piece packet
#
sub _build_piece_packet {
    my($args) = @_;

    _hash_defines($args, 'piece_index', 'block_offset', 'data_ref');

    my $packet_body = pack( 'NN', 
                            $args->{piece_index}, 
                            $args->{block_offset}
                           );

    return _build_packet( BT_PIECE, $packet_body, $args->{data_ref} );
}

#
# _build_cancel_packet PIECE_INDEX BIT_OFFSET BIT_LENGTH
#     Return a cancel packet
#
sub _build_cancel_packet {
    my($args) = @_;

    _hash_defines($args, 'piece_index', 'block_offset', 'block_size');

    my $packet_body = pack( 'NNN', 
                            $args->{piece_index}, 
                            $args->{block_offset}, 
                            $args->{block_size} 
                           );
    return _build_packet( BT_CANCEL, $packet_body );
}

#
# _build_packet BT_CODE PACKET_BODY DATA_REF
#     _build_packet ends up getting called by all of the _build_*_packet
#     subroutines.  This routine accepts the BitTorrent packet code (as
#     an integer), an optional packet body and optional data reference.
#
sub _build_packet {
    my ( $_code, $packet_body, $data_ref ) = @_;

    $packet_body = ''   unless defined $packet_body;
    $data_ref    = \ '' unless defined $data_ref;

    my $packet = pack(
        'NCa*a*',
        length( $packet_body ) + length(${$data_ref}) + 1,
        $_code,
        $packet_body,
        ${$data_ref}    );

    return $packet;
}

#
# _parse_have_packet PACKET_PAYLOAD
#     Return a parsed have packet
#
sub _parse_have_packet {
    my ($packet_ref) = @_;
    
    my ($piece_index) = unpack('N', $$packet_ref);
        
    return { 
             bt_code     => BT_HAVE, 
             piece_index => $piece_index 
           };
}

#
# _parse_bitfield_packet PACKET_PAYLOAD
#     Return a parsed bitfield packet
#
sub _parse_bitfield_packet {
    my ($packet_ref) = @_;
    
    return { 
             bt_code      => BT_BITFIELD, 
             bitfield_ref => $packet_ref,
           };
}

#
# _parse_request_packet PACKET_PAYLOAD
#     Return a parsed request packet
#
sub _parse_request_packet {
    my ($packet_ref) = @_;
    
    my ($piece_index, $block_offset, $block_size) 
        = unpack('NNN', $$packet_ref);
        
    return { 
             bt_code      => BT_REQUEST, 
             piece_index  => $piece_index,
             block_offset => $block_offset,
             block_size   => $block_size,
           };
}

#
# _parse_piece_packet PACKET_PAYLOAD
#     Return a parsed piece packet
#
sub _parse_piece_packet {
    my ($packet_ref) = @_;
    
    my ($piece_index, $block_offset) = unpack('NN', $$packet_ref);
    
    return { 
             bt_code      => BT_PIECE, 
             piece_index  => $piece_index,
             block_offset => $block_offset,
             data_ref     => \substr($$packet_ref, 8),
           };
}

#
# _parse_cancel_packet PACKET_PAYLOAD
#     Return a parsed cancel packet
#
sub _parse_cancel_packet {
    my ($packet_ref) = @_;
    
    my ($piece_index, $block_offset, $block_size) = unpack('NNN', $$packet_ref);
        
    return { 
             bt_code      => BT_CANCEL, 
             piece_index  => $piece_index,
             block_offset => $block_offset,
             block_size   => $block_size,
           };
}

#
# _hash_defines HASH_REFERENCE LIST_OF_KEYS
#     Makes sure that the given hash defines values for all keys in the list.
#
sub _hash_defines {
    my ($hash, @keys) = @_;
    
    ref $hash eq 'HASH'
        or croak("Hash reference not found");
        
    for my $key (@keys) {
        defined $hash->{$key}
            or croak("$key not specified");
    }
    
    return 1;
}

1;

=pod

=head1 NAME

  Net::BitTorrent::PeerPacket - Parse/Build Peer Packets from BitTorrent

=head1 SYNOPSIS 

  # Encode a packet
  my $binary_packet = bt_build_packet($key1, $value1, $key2, $value2);

  # Decode a packet
  my $parsed_packet = bt_parse_packet($binary_data);

=head1 DESCRIPTION

C<Net::BitTorrent::PeerPacket> handles parsing and building binary data 
shared between BitTorrent peers.  The module optinally exports a single
subroutine for building packets and another for parsing packets, as well
as, a constant for each packet type defined by BitTorrent.

=head1 CONSTANTS

There are nine primary types of packets that are shared between peers on a
BitTorrent network.  The following constants are how the type of packet
being build/parsed are represented within this module.

=over 4

=item BT_CHOKE

=item BT_UNCHOKE

=item BT_INTERESTED

=item BT_UNINTERESTED

=item BT_HAVE

=item BT_BITFIELD

=item BT_REQUEST

=item BT_PIECE

=item BT_CANCEL

=back

=head1 SUBROUTINES

=head2 bt_build_packet

This subroutine is responsible for building all types of BitTorrent packets.  
The arguments are passed into the subroutine as a list of key-value pairs.  
The resultant packet is sent back as a scalar.

Depending on the requested packet type, the required arguments vary.  One 
argument that is common to all calls is the bt_code.  The bt_code maps to a 
BT_ constant exported by this module and determines the type of packet that
will be built.

What follows is a list of the different BT codes and the details of calling
this subroutine with those codes.

=head3 BT_CHOKE

Passing the BT_CHOKE code causes a choke packet to be generated.  This type of
packet requires no additional data and therefore no additional arguments.

=head3 BT_UNCHOKE

Passing the BT_UNCHOKE code causes an unchoke packet to be generated.  This 
type of packet requires no additional data and therefore no additional 
arguments.

=head3 BT_INTERESTED

Passing the BT_INTERESTED code causes an interested packet to be generated.  
This type of packet requires no additional data and therefore no additional 
arguments.

=head3 BT_UNINTERESTED

Passing the BT_UNINTERESTED code causes an uninterested packet to be generated.  
This type of packet requires no additional data and therefore no additional 
arguments.

=head3 BT_HAVE

Passing the BT_HAVE code causes a have packet to be generated.  This type of 
packet requires a piece index in addition to the BT code.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=back

=head3 BT_BITFIELD

Passing the BT_BITFIELD code causes a bit field packet to be generated.  This 
type of packet requires the bit field be specified in addition to the BT code.

=over 4

=item bitfield_ref

The bit field is passed in as a reference to a scalar.  The scalar contains
binary data representing the pieces that are present and missing.

=back

=head3 BT_REQUEST

Passing the BT_REQUEST code causes a request packet to be generated.  This 
type of packet requires the piece index along with block offset and size in 
addition to the BT code.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=item block_offset

The block offset is the zero-based byte offset of the requested data within the
specified piece.

=item block_size

The block size is the size of the data requested.  Be sure not to set this
value too large, as some clients will end your connection if your request is
too big.

=back

=head3 BT_PIECE

Passing the BT_PIECE code causes a piece packet to be generated.  This 
type of packet requires the piece index along with block offset and the data
to be transfered in addition to the BT code.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=item block_offset

The block offset is the zero-based byte offset of the requested data within the
specified piece.

=item data_ref

The data reference is a reference to a scalar containing the data at the
specified block offset within the specified piece.

=back

=head3 BT_CANCEL

Passing the BT_CANCEL code causes a cancel packet to be generated.  This 
type of packet requires the piece index along with block offset and size in 
addition to the BT code.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=item block_offset

The block offset is the zero-based byte offset of the requested data within the
specified piece.

=item block_size

The block size is the size of the data requested.  Be sure not to set this
value too large, as some clients will end your connection if your request is
too big.

=back

=head2 bt_parse_packet

This subroutine is responsible for parsing all types of BitTorrent packets.  
It accepts a single argument, which is a reference to a scalar that contains
the raw packet data.  It returns a hash reference containing the parsed data.

Depending on the packet type, the keys in the returned hash vary.  One 
key that is common to all packets is the bt_code.  The bt_code maps to a 
BT_ constant exported by this module and reveals the type of packet that
was parsed.

What follows is a list of the different BT codes that might be returned and the
additional keys that will be packaged with each code.

=head3 BT_CHOKE

The resultant hash from a choke packet will only contain the 'bt_code' key.

=head3 BT_UNCHOKE

The resultant hash from an unchoke packet will only contain the 'bt_code' key.

=head3 BT_INTERESTED

The resultant hash from an interested packet will only contain the 'bt_code' 
key.

=head3 BT_UNINTERESTED

The resultant hash from an uninterested packet will only contain the 'bt_code' 
key.

=head3 BT_HAVE

The resultant hash from a have packet will only contain the 'bt_code' 
key and the following additional keys.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=back

=head3 BT_BITFIELD

The resultant hash from a bit field packet will only contain the 'bt_code' 
key and the following additional keys.

=over 4

=item bitfield_ref

The bit field is passed in as a reference to a scalar.  The scalar contains
binary data representing the pieces that are present and missing.

=back

=head3 BT_REQUEST

The resultant hash from a request packet will only contain the 'bt_code' 
key and the following additional keys.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=item block_offset

The block offset is the zero-based byte offset of the requested data within the
specified piece.

=item block_size

The block size is the size of the data requested.  Be sure not to set this
value too large, as some clients will end your connection if your request is
too big.

=back

=head3 BT_PIECE

The resultant hash from a piece packet will only contain the 'bt_code' 
key and the following additional keys.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=item block_offset

The block offset is the zero-based byte offset of the requested data within the
specified piece.

=item data_ref

The data reference is a reference to a scalar containing the data at the
specified block offset within the specified piece.

=back

=head3 BT_CANCEL

The resultant hash from a cancel packet will only contain the 'bt_code' 
key and the following additional keys.

=over 4

=item piece_index

The piece index is the zero-based numeric index of a piece within a torrent.

=item block_offset

The block offset is the zero-based byte offset of the requested data within the
specified piece.

=item block_size

The block size is the size of the data requested.  Be sure not to set this
value too large, as some clients will end your connection if your request is
too big.

=back

=head1 INSTALL

  perl Build.PL
  ./Build
  ./Build test
  ./Build install

=head1 AUTHOR

Josh McAdams <joshua dot mcadams at gmail dot com>

=cut

__END__
