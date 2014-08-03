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
use strict;
use warnings;

our $VERSION = '0.02';
$Data::Dumper::Indent = 1;

my $api_key_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.key');
my ($api_key, $api_secret) = retrieve_key_info();

my $flickr = Flickr::API2->new({'key' => $api_key, secret => $api_secret});
my $user   = $flickr->people->findByUsername('kevinspencer')->getInfo();

# to find the total number of photos, we need to know the initial epoch of the first upload...
# FIXME: this should all be handled in Flickr::API2::People...
my $epoch_first_photo = $user->{photos}{firstdate}{_content}; # <== #FIXME, um, method calls much?
print $epoch_first_photo, "\n";

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
