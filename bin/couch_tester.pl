#!/usr/bin/perl

### LPC SAMPLE DEFERRED MSGLITE HANDLER ###

# This daemon listens to msglite for incoming web requests that were
# re-directed or initiated by a normal web request. it demonstrates how
# to handle a deferred lower priority request

use strict;

use Data::Dumper;
use Time::HiRes;
use POSIX;
use LWP::UserAgent;
use HTTP::Request;
use JSON;

use LabZero::Fail;
use LabZero::Couch;
use LabZero::Context;

$| = 1;

my $base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
my $epoch = 5333333333;

my $test_url = 'http://lpc.bizzblizz.net/app/Sample';
my $ua = LWP::UserAgent->new('COUCHY');
my $couch_url = 'http://127.0.0.1:5984/';

my $context = LabZero::Context->load();
my $couch = $context->couchdb();

# my $infew = $couch->info('foo');
# print "> " . Dumper($infew) . "\n";

my $doccy = $couch->get_doc( foo => 'ab8eaaaacdcR');
print "> " . Dumper($doccy) . "\n";

$doccy->{count} += 1;

my $result = $couch->save_doc(foo => $doccy);
print "> " . Dumper($result) . "\n";

my $result = $couch->update_doc(foo => 'acaraaaacdnL', sub {
	$_[0]->{stringle} .= 'x';
});
print "> " . Dumper($result) . "\n";

# my $doccy = $couch->get_doc( foo => 'my_first_record');
# my $resulty = $couch->delete_doc( foo => 'my_first_record', $doccy->{'_rev'});
# print "> " . Dumper($doccy) . "\n";

# my $doccy = $couch->new_doc( foo => {
# 	oranges => 'they are a fruit',
# 	comment => 'oh yes they are!',
# });
# print "> $doccy\n";
