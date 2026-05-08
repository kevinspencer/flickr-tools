#!/usr/bin/env perl
# Copyright 2026 Kevin Spencer <kevin@kevinspencer.org>
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
use File::Spec;
use Flickr::API;
use Getopt::Long;
use strict;
use warnings;

our $VERSION = '1.00';

my $flickr_username;
GetOptions("user=s" => \$flickr_username);
die "Need to pass in username.  Usage: ./list-albums.pl --user vek\n" unless $flickr_username;

my $config_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.st');
die "OAuth config not found at $config_file - run gen-auth-token.pl first.\n" unless -e $config_file;

my $api = Flickr::API->import_storable_config($config_file);

my $response = $api->execute_method('flickr.urls.lookupUser', { url => "https://www.flickr.com/photos/$flickr_username/" });
die "Could not find user '$flickr_username': " . $response->error_message() . "\n" unless $response->success();
my $data = $response->as_hash();
my $nsid = $data->{user}{id};

$response = $api->execute_method('flickr.photosets.getList', { user_id => $nsid, per_page => 500 });
die "Could not get albums: " . $response->error_message() . "\n" unless $response->success();
$data = $response->as_hash();

my $sets = $data->{photosets}{photoset};
$sets = [$sets] if ref($sets) eq 'HASH';

if (!$sets || !@$sets) {
    print "No albums found for $flickr_username.\n";
    exit;
}

printf "%-20s  %-6s  %s\n", 'Album ID', 'Photos', 'Title';
printf "%s\n", '-' x 70;
for my $set (@$sets) {
    printf "%-20s  %-6s  %s\n", $set->{id}, $set->{photos}, $set->{title};
}
print "\nTotal: " . scalar(@$sets) . " albums\n";
