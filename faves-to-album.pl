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

# experimental, Flickr::API2 on the CPAN doesn't support count_faves()
use lib '/Users/kevin/code/Flickr-API2/lib';
use Data::Dumper;
use File::HomeDir;
use File::Spec;
use Flickr::API2;
use POSIX qw(ceil);
use strict;
use warnings;

our $VERSION = '0.03';
$Data::Dumper::Indent = 1;

my $api_key_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.key');
my ($api_key, $api_secret) = retrieve_key_info();

my $flickr = Flickr::API2->new({'key' => $api_key, secret => $api_secret});

my $user   = $flickr->people->findByUsername('kevinspencer');
my $info   = $user->getInfo();

my $total_photos = $info->{photos}{count}{_content};

# flickr.people.getPublicPhotos can handle 500 photos per 'page' request...
my $photos_per_page = $total_photos >= 500 ? 500 : $total_photos;
my $pages_needed    = ceil($total_photos / $photos_per_page);
my $current_counter = $photos_per_page;
for my $current_page_count (1..$pages_needed) {
    my @photos = $user->getPublicPhotos(per_page => $photos_per_page, page => $current_page_count);
    my $count = @photos;
    print "$current_page_count => $current_counter => got $count photos back from the Flickrs\n";
    $current_counter += $photos_per_page;
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
