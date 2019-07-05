#!/usr/bin/env perl
# Copyright 2019 Kevin Spencer <kevin@kevinspencer.org>
#
# Permission to use, copy, modify, distribute, and sell this software and its
# documentation for any purpose is hereby granted without fee, provided that
# the above copyright notice appear in all copies and that both that
# copyright notice and this permission notice appear in supporting
# documentation. No representations are made about the suitability of this
# software for any purpose. It is provided "as is" without express or
# implied warranty.
#
################################################################################

use Encode::Base58;
use strict;
use warnings;

our $VERSION = '0.01';

my $original_photo_url = shift;

if (! $original_photo_url) {
    die "Needs a photo URL\n";
}

my $flickr_short_base_url = 'https://flic.kr/p';

if ($original_photo_url =~ /(\d+)$/) {
    my $photo_id = $1;
    
    my $shortened_url = $flickr_short_base_url . '/' . encode_base58($photo_id);

    print $shortened_url, "\n";
}
