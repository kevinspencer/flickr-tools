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
use strict;
use warnings;

our $VERSION = '1.00';

binmode(STDOUT, ':utf8');

my $photo_url = shift or die "Usage: ./thanks.pl <flickr-photo-url>\n";

my ($photo_id) = $photo_url =~ m{/photos/[^/]+/(\d+)};
die "Could not extract photo ID from URL: $photo_url\n" unless $photo_id;

my $config_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.st');
die "OAuth config not found at $config_file - run gen-auth-token.pl first.\n" unless -e $config_file;

my $api = Flickr::API->import_storable_config($config_file);

my $response = $api->execute_method('flickr.photos.comments.getList', { photo_id => $photo_id });
die "Could not get comments: " . $response->error_message() . "\n" unless $response->success();

my $data     = $response->as_hash();
my $comments = $data->{comments}{comment};

if (!$comments) {
    print "No comments found on this photo.\n";
    exit;
}

$comments = [$comments] if ref($comments) eq 'HASH';

# Collect unique authors in order of first appearance
my %seen;
my @authors;
for my $comment (@$comments) {
    my $nsid = $comment->{author};
    next if $seen{$nsid}++;
    push @authors, $nsid;
}

print join("\n", map { "[https://www.flickr.com/photos/$_]" } @authors);
print "\n\nThank you all so much.\n";
