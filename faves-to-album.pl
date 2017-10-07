#!/usr/bin/env perl
# Copyright 2014-2017 Kevin Spencer <kevin@kevinspencer.org>
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

our $VERSION = '0.16';

$Data::Dumper::Indent = 1;

my ($favorite_count_threshold, $flickr_username);
GetOptions("count=i" => \$favorite_count_threshold, "user=s" => \$flickr_username);
if (! $favorite_count_threshold) {
    print "Count not passed in, defaulting to 10...\n";
    $favorite_count_threshold = 10;
}

if (! $flickr_username) {
    die "Need to pass in username.  Usage: ./faves-to-album.pl --user kevinspencer\n";
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
    my $set_id          = find_or_create_set($favorite_count_threshold, $random_photo_id);

    my $add_count = add_photos_to_album($photos_to_move, $set_id);

    $photo_word   = $add_count == 1 ? 'photo' : 'photos';

    print "Added $add_count $photo_word on this run\n";
    print "Cleaning up...\n";

    remove_photos_from_album($set_id);
}

sub find_or_create_set {
    my ($count, $photo_id) = @_;

    my $user = $flickr->people->findByUsername($flickr_username);
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
    print "$set_title did not exist, created it.\n";
    return $id;
}

sub get_photos_above_threshold {
    my $user   = $flickr->people->findByUsername($flickr_username);
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

# FIXME: duplication of code here from get_photos_above_threshold(), refactor

sub get_photos_from_set {
    my $set_id = shift;

    my $user = $flickr->people->findByUsername($flickr_username);

    # how many photos are in this set already?
    my $count = $user->photosetGetPhotoCount($set_id);

    # flickr.photosets.getPhotos can handle 500 photos per 'page' request...
    my $photos_per_page = $count >= 500 ? 500 : $count;
    my $pages_needed    = ceil($count / $photos_per_page);
    my $current_counter = $photos_per_page;

    my %photos_in_set;
    for my $current_page_count (1..$pages_needed) {
        my @photos = $user->photosetGetPhotos($set_id, (per_page => $photos_per_page, page => $current_page_count));
        for my $photo (@photos) {
            if ($photo->{count_faves} >= $favorite_count_threshold) {
                $photos_in_set{$photo->{id}}{count} = $photo->{count_faves};
                $photos_in_set{$photo->{id}}{title} = $photo->{title};
            }
        }
    }
    return %photos_in_set ? \%photos_in_set : undef;
}

sub add_photos_to_album {
    my ($photos_to_add, $set_id) = @_;

    my $user = $flickr->people->findByUsername($flickr_username);


    # weed out those photos already in set...
    my $photos_in_set = get_photos_from_set($set_id);
    for my $photo_in_set (keys(%$photos_in_set)) {
        if ($photos_to_add->{$photo_in_set}) {
            delete $photos_to_add->{$photo_in_set};
        }
    }

    # let's make sure we handle unicode in our photo names...
    binmode STDOUT, ":utf8";

    my $what_is_left = keys(%$photos_to_add);
    print "Found $what_is_left not already in the set\n";

    my $count = 0;
    PHOTOLOOP:
    for my $photo_id (keys(%$photos_to_add)) {
        RETRYLOOP:
        for my $current_attempt_count (1..3) {
            eval {
                $user->addtoPhotoset(photo_id => $photo_id, photoset_id =>$set_id);
            };
            if ($@) {
                next PHOTOLOOP if ($@ =~ /Photo already in set/);
                # if the Flickr API returns with a 5xx, retry if we can...
                if ($current_attempt_count == 3) {
                    die $@;
                }
                next RETRYLOOP if ($@ =~ /API call failed with HTTP status: 5/);
                # if we're here it's not an error we know how to deal with so just bail...
                die $@;
            }
            last RETRYLOOP;
        }
        $count++;
        print "Added $photos_to_add->{$photo_id}{title}...\n";
    }
    
    return $count;
}

sub remove_photos_from_album {
    my $set_id = shift;

    my $user = $flickr->people->findByUsername($flickr_username);

    my @photos = $user->photosetGetPhotos($set_id);
    my $count  = @photos ? @photos : 0;
    my $plural_word = $count == 1 ? 'photo' : 'photos';

    print "Found $count $plural_word already in set, checking for under threshold of $favorite_count_threshold...\n";

    my $did_removal = 0;
    for my $photo (@photos) {
        if ($photo->{count_faves} < $favorite_count_threshold) {
            print "Found $photo->{title}, only has $photo->{count_faves} faves, deleting...\n";
            $user->removefromPhotoset($photo->{id}, $set_id);
            $did_removal = 1;
        }
    }
    print "No photos found to remove under threshold of $favorite_count_threshold...\n" if (! $did_removal);
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
    } else {
        die "Hmm, looks like $api_key_file doesn't exist, cannot continue.\n";
    }
    return;
}
