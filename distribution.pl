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

our $VERSION = '1.01';

my ($type, $flickr_username);
GetOptions("type=s" => \$type, "user=s" => \$flickr_username);

if (!$type) {
    print "No --type passed in, defaulting to faves...\n";
    $type = 'faves';
}

if (!$flickr_username) {
    die "Need to pass in username.  Usage: ./distribution.pl --user kevinspencer\n";
}

my %type_map = (faves => 'count_faves', views => 'views');
die "Unknown type '$type'. Valid types: faves, views\n" unless $type_map{$type};

my $cache_dir  = 'cache';
my $cache_file = "$cache_dir/photos_$flickr_username.json";
make_path($cache_dir);

my $config_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.st');
die "OAuth config not found at $config_file - run gen-auth-token.pl first.\n" unless -e $config_file;

my @photos;
if (-f $cache_file && prompt_use_cache($cache_file)) {
    @photos = @{ load_cache($cache_file) };
    print "Loaded " . scalar(@photos) . " photos from cache.\n";
} else {
    my $api = Flickr::API->import_storable_config($config_file);

    my $response = $api->execute_method('flickr.urls.lookupUser', { url => "https://www.flickr.com/photos/$flickr_username/" });
    die "Could not find user '$flickr_username': " . $response->error_message() . "\n" unless $response->success();
    my $data = $response->as_hash();
    my $nsid = $data->{user}{id};

    $response = $api->execute_method('flickr.people.getInfo', { user_id => $nsid });
    die "Could not get user info: " . $response->error_message() . "\n" unless $response->success();
    $data = $response->as_hash();
    my $total_photos = $data->{person}{photos}{count};
    print "Found $total_photos photos...\n";

    my $photos_per_page = $total_photos >= 500 ? 500 : $total_photos;
    my $pages_needed    = ceil($total_photos / $photos_per_page);
    print "Retrieving photos in page batches of $photos_per_page...\n";
    print "Need $pages_needed page requests to complete distribution...\n";

    my $total_processed = 0;
    for my $page (1..$pages_needed) {
        $response = $api->execute_method('flickr.people.getPublicPhotos', {
            user_id  => $nsid,
            per_page => $photos_per_page,
            page     => $page,
            extras   => 'count_faves,views',
        });
        die "Could not get photos (page $page): " . $response->error_message() . "\n" unless $response->success();
        $data = $response->as_hash();

        my $page_photos = $data->{photos}{photo};
        $page_photos = [$page_photos] if ref($page_photos) eq 'HASH';

        for my $photo (@$page_photos) {
            push @photos, { count_faves => $photo->{count_faves}, views => $photo->{views} };
        }
        $total_processed += scalar(@$page_photos);
        print "Completed page $page, $total_processed photos processed...\n";
    }

    write_cache($cache_file, \@photos);
    print "Cache written to $cache_file\n";
}

my %distribution;
for my $photo (@photos) {
    $distribution{$photo->{$type_map{$type}}}++;
}

my $label = $type eq 'faves' ? 'Faves' : 'Views';
print "$label, Photos\n";
for my $count (sort { $b <=> $a } keys(%distribution)) {
    print "$count, $distribution{$count}\n";
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
