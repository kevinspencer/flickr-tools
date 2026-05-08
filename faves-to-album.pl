#!/usr/bin/env perl
# Copyright 2014-2026 Kevin Spencer <kevin@kevinspencer.org>
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

use File::HomeDir;
use File::Path qw(make_path);
use File::Spec;
use Flickr::API;
use Getopt::Long;
use JSON;
use POSIX qw(ceil);
use strict;
use warnings;

our $VERSION = '1.00';

binmode(STDOUT, ':utf8');

my ($favorite_count_threshold, $flickr_username);
GetOptions("count=i" => \$favorite_count_threshold, "user=s" => \$flickr_username);

if (!$favorite_count_threshold) {
    print "Count not passed in, defaulting to 10...\n";
    $favorite_count_threshold = 10;
}

die "Need to pass in username.  Usage: ./faves-to-album.pl --user vek\n" unless $flickr_username;

my $cache_dir  = 'cache';
my $cache_file = "$cache_dir/photos_$flickr_username.json";
make_path($cache_dir);

my $config_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.st');
die "OAuth config not found at $config_file - run gen-auth-token.pl first.\n" unless -e $config_file;

my $api = Flickr::API->import_storable_config($config_file);

my $nsid = lookup_nsid($flickr_username);

# Load all public photos (from cache or API)
my @all_photos;
if (-f $cache_file && prompt_use_cache($cache_file)) {
    @all_photos = @{ load_cache($cache_file) };
    print "Loaded " . scalar(@all_photos) . " photos from cache.\n";
} else {
    @all_photos = fetch_all_photos($nsid);
    write_cache($cache_file, \@all_photos);
    print "Cache written to $cache_file\n";
}

# Find photos above threshold
my %photos_to_move;
for my $photo (@all_photos) {
    if ($photo->{count_faves} >= $favorite_count_threshold) {
        $photos_to_move{$photo->{id}}{count} = $photo->{count_faves};
        $photos_to_move{$photo->{id}}{title} = $photo->{title};
    }
}

if (!%photos_to_move) {
    print "Found no photos above threshold of $favorite_count_threshold, exiting.\n";
    exit();
}

my $count      = keys(%photos_to_move);
my $photo_word = $count == 1 ? 'photo' : 'photos';
print "Found $count $photo_word above threshold of $favorite_count_threshold\n";

my @photo_id_keys   = keys(%photos_to_move);
my $random_photo_id = $photo_id_keys[rand @photo_id_keys];
my $set_id          = find_or_create_set($favorite_count_threshold, $random_photo_id);

my $add_count = add_photos_to_album(\%photos_to_move, $set_id);
$photo_word   = $add_count == 1 ? 'photo' : 'photos';
print "Added $add_count $photo_word on this run\n";

print "Cleaning up...\n";
remove_photos_from_album($set_id);

# --- Subs ---

sub lookup_nsid {
    my ($username) = @_;
    my $response = $api->execute_method('flickr.urls.lookupUser', { url => "https://www.flickr.com/photos/$username/" });
    die "Could not find user '$username': " . $response->error_message() . "\n" unless $response->success();
    return $response->as_hash()->{user}{id};
}

sub fetch_all_photos {
    my ($user_nsid) = @_;

    my $response = $api->execute_method('flickr.people.getInfo', { user_id => $user_nsid });
    die "Could not get user info: " . $response->error_message() . "\n" unless $response->success();
    my $total_photos = $response->as_hash()->{person}{photos}{count};

    my $photos_per_page = $total_photos >= 500 ? 500 : $total_photos;
    my $pages_needed    = ceil($total_photos / $photos_per_page);
    print "Fetching $total_photos photos in $pages_needed page requests...\n";

    my @photos;
    for my $page (1..$pages_needed) {
        my $r = $api->execute_method('flickr.people.getPublicPhotos', {
            user_id  => $user_nsid,
            per_page => $photos_per_page,
            page     => $page,
            extras   => 'count_faves,views',
        });
        die "Could not get photos (page $page): " . $r->error_message() . "\n" unless $r->success();
        my $data        = $r->as_hash();
        my $page_photos = $data->{photos}{photo};
        $page_photos    = [$page_photos] if ref($page_photos) eq 'HASH';
        for my $photo (@$page_photos) {
            push @photos, {
                id          => $photo->{id},
                title       => $photo->{title},
                count_faves => $photo->{count_faves},
                views       => $photo->{views},
            };
        }
        print "Completed page $page, " . scalar(@photos) . " photos fetched...\n";
    }
    return @photos;
}

sub find_or_create_set {
    my ($threshold, $primary_photo_id) = @_;

    my $response = $api->execute_method('flickr.photosets.getList', { user_id => $nsid, per_page => 500 });
    die "Could not get albums: " . $response->error_message() . "\n" unless $response->success();
    my $sets = $response->as_hash()->{photosets}{photoset};
    $sets = [$sets] if ref($sets) eq 'HASH';

    my $set_title = "$threshold faves or more";
    for my $set (@$sets) {
        return $set->{id} if $set->{title} eq $set_title;
    }

    # Create it
    $response = $api->execute_method('flickr.photosets.create', {
        title            => $set_title,
        primary_photo_id => $primary_photo_id,
    });
    die "Could not create album '$set_title': " . $response->error_message() . "\n" unless $response->success();
    print "'$set_title' did not exist, created it.\n";
    return $response->as_hash()->{photoset}{id};
}

sub get_photos_from_set {
    my ($set_id) = @_;

    # Get total count first
    my $response = $api->execute_method('flickr.photosets.getPhotos', {
        photoset_id => $set_id,
        user_id     => $nsid,
        per_page    => 1,
        extras      => 'count_faves',
    });
    die "Could not get album photos: " . $response->error_message() . "\n" unless $response->success();
    my $total        = $response->as_hash()->{photoset}{total} // 0;
    my $pages_needed = $total > 0 ? ceil($total / 500) : 0;

    return {} unless $total;

    my %photos_in_set;
    for my $page (1..$pages_needed) {
        $response = $api->execute_method('flickr.photosets.getPhotos', {
            photoset_id => $set_id,
            user_id     => $nsid,
            per_page    => 500,
            page        => $page,
            extras      => 'count_faves',
        });
        die "Could not get album photos (page $page): " . $response->error_message() . "\n" unless $response->success();
        my $page_photos = $response->as_hash()->{photoset}{photo};
        $page_photos = [$page_photos] if ref($page_photos) eq 'HASH';
        for my $photo (@$page_photos) {
            $photos_in_set{$photo->{id}}{count} = $photo->{count_faves};
            $photos_in_set{$photo->{id}}{title} = $photo->{title};
        }
    }
    return \%photos_in_set;
}

sub add_photos_to_album {
    my ($photos_to_add, $set_id) = @_;

    my $photos_in_set = get_photos_from_set($set_id);

    # Remove those already in set
    for my $photo_id (keys(%$photos_in_set)) {
        delete $photos_to_add->{$photo_id};
    }

    my $remaining = keys(%$photos_to_add);
    print "Found $remaining not already in the album\n";

    my $count = 0;
    PHOTOLOOP:
    for my $photo_id (keys(%$photos_to_add)) {
        RETRYLOOP:
        for my $attempt (1..3) {
            my $response = $api->execute_method('flickr.photosets.addPhoto', {
                photoset_id => $set_id,
                photo_id    => $photo_id,
            });
            if (!$response->success()) {
                next PHOTOLOOP if $response->error_code() == 3; # already in set
                if ($attempt == 3) {
                    die "Failed to add photo $photo_id: " . $response->error_message() . "\n";
                }
                next RETRYLOOP if $response->rc() =~ /^5/;
                die "Failed to add photo $photo_id: " . $response->error_message() . "\n";
            }
            last RETRYLOOP;
        }
        $count++;
        print "Added $photos_to_add->{$photo_id}{title}...\n";
    }
    return $count;
}

sub remove_photos_from_album {
    my ($set_id) = @_;

    my $photos_in_set = get_photos_from_set($set_id);
    my $count         = scalar(keys(%$photos_in_set));
    my $plural_word   = $count == 1 ? 'photo' : 'photos';

    print "Found $count $plural_word in album, checking for any under threshold of $favorite_count_threshold...\n";

    my $did_removal = 0;
    for my $photo_id (keys(%$photos_in_set)) {
        my $faves = $photos_in_set->{$photo_id}{count};
        if ($faves < $favorite_count_threshold) {
            print "Removing $photos_in_set->{$photo_id}{title} ($faves faves)...\n";
            my $response = $api->execute_method('flickr.photosets.removePhoto', {
                photoset_id => $set_id,
                photo_id    => $photo_id,
            });
            if (!$response->success()) {
                print "Warning: could not remove photo $photo_id: " . $response->error_message() . "\n";
                next;
            }
            $did_removal = 1;
        }
    }
    print "No photos found to remove under threshold of $favorite_count_threshold\n" unless $did_removal;
}

sub prompt_use_cache {
    my ($file) = @_;
    my $age     = time() - (stat($file))[9];
    my $age_str = $age < 3600 ? int($age / 60) . ' minutes' : int($age / 3600) . ' hours';
    print "Cache exists (age: $age_str). Use cached data? [y/n] ";
    chomp(my $answer = <STDIN>);
    return lc($answer) eq 'y';
}

sub load_cache {
    my ($file) = @_;
    open(my $fh, '<', $file) or die "Cannot read cache $file: $!\n";
    my $json = do { local $/; <$fh> };
    close($fh);
    return decode_json($json);
}

sub write_cache {
    my ($file, $data) = @_;
    open(my $fh, '>', $file) or die "Cannot write cache $file: $!\n";
    print $fh encode_json($data);
    close($fh);
}
