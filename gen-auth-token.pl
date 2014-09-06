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

# experimental, Flickr::API2 on the CPAN doesn't quite implement auth...
use lib '/Users/kevin/code/Flickr-API2/lib';
use File::HomeDir;
use File::Spec;
use Flickr::API2;
use IO::Prompt;
use strict;
use warnings;

our $VERSION = '0.01';

my $api_key_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.key');
my ($api_key, $api_secret) = retrieve_key_info();

my $flickr = Flickr::API2->new({'key' => $api_key, secret => $api_secret});

my $response = $flickr->execute_method('flickr.auth.getFrob');
my $frob     = $response->{frob}{_content};
my $user     = $flickr->people->findByUsername('kevinspencer');
my $url      = $user->getAuthURL('write', $frob);

print "Visit the following URL to authorize access:\n$url\n";

my $ok_to_continue = prompt("Once done, hit enter to continue: ");

$response = $flickr->execute_method('flickr.auth.getToken', { frob => $frob });
my $token = $response->{token}{_content};

print "Auth token is: $token\n";

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
