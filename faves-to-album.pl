#!/usr/bin/env perl
# Copyright 2014-2015 Kevin Spencer <kevin@kevinspencer.org>
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

# experimental, Flickr::API2 on the CPAN doesn't have native support for sets
use lib '/Users/kevin/code/Flickr-API2/lib';
use Data::Dumper;
use File::HomeDir;
use File::Spec;
use Flickr::API2;
use Getopt::Long;
use POSIX qw(ceil);
use strict;
use warnings;

our $VERSION = '0.10';
$Data::Dumper::Indent = 1;

my $favorite_count_threshold;
GetOptions("count=i" => \$favorite_count_threshold);
if (! $favorite_count_threshold) {
    print "Count not passed in, defaulting to 10...\n";
    $favorite_count_threshold = 10;
}

my $api_key_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.key');
my ($api_key, $api_secret, $auth_token) = retrieve_key_info();

my $flickr = Flickr::API2->new({'key' => $api_key, secret => $api_secret, token => $auth_token});

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

    # check to see if we already have an album on Flickr called "$favorite_count_threshold or more" 
    # and create it if we don't.  we need to pass in a primary_photo_id if creating...
    my @photo_id_keys   = keys(%$photos_to_move);
    my $random_photo_id = $photo_id_keys[rand @photo_id_keys];
    my $set_id = find_or_create_set($favorite_count_threshold, $random_photo_id);
    my $add_count = add_photos_to_album($photos_to_move, $set_id);
    $photo_word = $add_count == 1 ? 'photo' : 'photos';
    print "Added $add_count $photo_word on this run\n";
    print "Cleaning up...\n";
    remove_photos_from_album($set_id);
}

sub find_or_create_set {
    my ($count, $photo_id) = @_;

    my $user = $flickr->people->findByUsername('kevinspencer');
    my @sets = $user->photosetGetList();

    my $set_title = "$count faves or more";
    my $set_id;
    for my $set (@sets) {
        if ($set->{title} eq $set_title) {
            $set_id = $set->{id};
            last;
        }
    }
    return $set_id if $set_id;

    # no set found so we'll create it...
    my $id = $user->photosetCreate(primary_photo_id => $photo_id, title => $set_title);
    return $id;
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

sub add_photos_to_album {
    my ($photos, $set_id) = @_;

    my $user =$flickr->people->findByUsername('kevinspencer');

    my $count = 0;
    for my $photo_id (keys(%$photos)) {
        eval {
            $user->addtoPhotoset(photo_id => $photo_id, photoset_id =>$set_id);
        };
        if ($@) {
            die $@ if ($@ !~ /Photo already in set/);
            next;
        }
        $count++;
        print "Added $photos->{$photo_id}{title}...\n";
    }
    
    return $count;
}

sub remove_photos_from_album {
    my $set_id = shift;

    my $user = $flickr->people->findByUsername('kevinspencer');

    my @photos = $user->photosetGetPhotos($set_id);
    my $count  = @photos ? @photos : 0;
    my $plural_word = $count == 1 ? 'photo' : 'photos';

    print "Found $count $plural_word already in set, checking for under threshold of $favorite_count_threshold...\n";

    for my $photo (@photos) {
        if ($photo->{count_faves} < $favorite_count_threshold) {
            print "Found $photo->{title}, only has $photo->{count_faves} faves, deleting...\n";
            $user->removefromPhotoset($photo->{id}, $set_id);
        }
    }
}

sub retrieve_key_info {
    if (-e $api_key_file) {
        open(my $fh, '<', $api_key_file) || die "Could not read $api_key_file - $!\n";
        my $api_key = <$fh>;
        chomp($api_key);
        my $api_secret = <$fh>;
        chomp($api_secret);
        my $auth_token = <$fh>;
        chomp($auth_token);
        close($fh);
        return ($api_key, $api_secret, $auth_token);
    }
    return;
}
