#!/usr/bin/env perl
# Copyright 2014 Kevin Spencer <kevin@kevinspencer.org>
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

use Data::Dumper;
use File::HomeDir;
use File::Spec;
use Flickr::API2;
use Getopt::Long;
use POSIX qw(ceil);
use strict;
use warnings;

our $VERSION = '0.04';
$Data::Dumper::Indent = 1;

my $favorite_count_threshold;
GetOptions("count=i" => \$favorite_count_threshold);
if (! $favorite_count_threshold) {
    print "Count not passed in, defaulting to 10...\n";
    $favorite_count_threshold = 10;
}

my $api_key_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.key');
my ($api_key, $api_secret) = retrieve_key_info();

my $flickr = Flickr::API2->new({'key' => $api_key, secret => $api_secret});

main();

sub main {
    my $photos_to_move = get_photos_above_threshold();

    if (! $photos_to_move) {
        print "Found no photos above threshold of $favorite_count_threshold, exiting.\n";
        exit();
    }

    my $count = keys(%$photos_to_move);
    my $photo_word = $count == 1 ? 'photo' : 'photos';
    print "Found $count $photo_word above threshold of $favorite_count_threshold\n";

    # TODO: check to see if we already have an album on Flickr called "$favorite_count_threshold or more" 
}

sub get_photos_above_threshold {
    my $user   = $flickr->people->findByUsername('kevinspencer');
    my $info   = $user->getInfo();

    my $total_photos = $info->{photos}{count}{_content};

    # flickr.people.getPublicPhotos can handle 500 photos per 'page' request...
    my $photos_per_page = $total_photos >= 500 ? 500 : $total_photos;
    my $pages_needed    = ceil($total_photos / $photos_per_page);
    my $current_counter = $photos_per_page;
    print "Checking Flickr for photos >= count threshold of $favorite_count_threshold ($total_photos photos)...\n";
    my %photos_to_move;
    for my $current_page_count (1..$pages_needed) {
        my @photos = $user->getPublicPhotos(per_page => $photos_per_page, page => $current_page_count);
        for my $photo (@photos) {
            if ($photo->{count_faves} >= $favorite_count_threshold) {
                $photos_to_move{$photo->{id}}{count} = $photo->{count_faves};
                $photos_to_move{$photo->{id}}{title} = $photo->{title};
            }
        }
    }
    return %photos_to_move ? \%photos_to_move : undef;
}

sub retrieve_key_info {
    if (-e $api_key_file) {
        open(my $fh, '<', $api_key_file) || die "Could not read $api_key_file - $!\n";
        my $api_key = <$fh>;
        chomp($api_key);
        my $api_secret = <$fh>;
        chomp($api_secret);
        close($fh);
        return ($api_key, $api_secret);
    }
    return;
}
