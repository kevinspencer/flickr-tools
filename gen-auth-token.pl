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
use File::Spec;
use Flickr::API;
use strict;
use warnings;

our $VERSION = '1.00';

my $api_key_file = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.key');
my $config_file  = File::Spec->catfile(File::HomeDir->my_home(), '.flickr.st');

my ($consumer_key, $consumer_secret) = retrieve_key_info();

my $api = Flickr::API->new({
    consumer_key    => $consumer_key,
    consumer_secret => $consumer_secret,
    callback        => 'https://127.0.0.1/',
});

my $rt_rc = $api->oauth_request_token({ callback => 'https://127.0.0.1/' });
die "Failed to get request token\n" if $rt_rc ne 'ok';

my $uri = $api->oauth_authorize_uri({ perms => 'write' });

print "\nVisit the following URL to authorize access:\n\n$uri\n\n";
print "Copy the redirect URL from your browser's address bar and paste it here:\n";

my $redirect_url = <STDIN>;
chomp($redirect_url);

my ($base, $query) = split(/\?/, $redirect_url);
die "Couldn't parse the redirect URL, please try again.\n" unless $query;

my %request_token;
for my $pair (split(/&/, $query)) {
    my ($key, $val) = split(/=/, $pair, 2);
    $key =~ s/^oauth_//;
    $request_token{$key} = $val;
}

die "Couldn't find oauth_verifier in the URL.\n" unless $request_token{verifier};

my $ac_rc = $api->oauth_access_token(\%request_token);
die "Failed to get access token\n" if $ac_rc ne 'ok';

$api->export_storable_config($config_file);
print "\nSuccess! OAuth config saved to $config_file\n";
print "You can now run the other flickr-tools scripts.\n";

sub retrieve_key_info {
    open(my $fh, '<', $api_key_file) || die "Could not read $api_key_file: $!\nCreate it with your API key on line 1 and secret on line 2.\n";
    my $key    = <$fh>; chomp($key);
    my $secret = <$fh>; chomp($secret);
    close($fh);
    return ($key, $secret);
}
