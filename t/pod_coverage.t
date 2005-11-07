#!/usr/bin/perl

use strict;
use warnings;
use Test::Pod::Coverage tests=>1;

pod_coverage_ok(
    "Net::BitTorrent::PeerPacket",
    "Net::BitTorrent::PeerPacket is covered",
);
