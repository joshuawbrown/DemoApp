#!/usr/bin/perl

### LPC SAMPLE DEFERRED MSGLITE HANDLER ###

# This daemon listens to msglite for incoming web requests that were
# re-directed or initiated by a normal web request. it demonstrates how
# to handle a deferred lower priority request

use strict;

use LabZero::Fail;

use Time::HiRes;
use LWP::UserAgent;
use HTTP::Request;

$| = 1;

my $test_url = 'http://lpc.bizzblizz.net/app/Sample';

my $last_output = time() + 10;
my $total_time = 0;
my $limit = 50000;

for my $i (1..$limit) {
	
	my ($stuff, $time) = http_get($test_url);
	$total_time += $time;
	my $elapsed = sprintf("%.3f", $total_time);
	
	if (time() > $last_output) {
		print "[$i] ", length($stuff), "Bytes, $elapsed sec\n";
		$last_output = time() + 10;
	}

}

my $req_per_sec = $limit / $total_time;
print "> ", sprintf("%.3f", $total_time), "sec, " . sprintf("%.3f", $req_per_sec) . " rps\n";


#################
### HTTP GET ###
#################

sub http_get {

	my ($url) = @_;
	
	my $ua = LWP::UserAgent->new('TESTER');
	my $elapsed;
	
	my $response = eval {
		local $SIG{ALRM} = sub { die("HTTP Post Error\nURL: $url\ERR: Timed Out after 60 seconds\n") };
		alarm 60;
		my $start = Time::HiRes::time();
		my $server_reply = $ua->get($url);
		$elapsed = Time::HiRes::time() - $start;
		alarm 0;
		return $server_reply;
	};
	
	if ($@) { die("HTTP GET Error\nURL: $url\nERR: $@\n"); }
	
	if ($response->code != 200) {
		my $error_message = $response->content . '(' . $response->code . ')';
		die("HTTP GET Error\nURL: $url\nERR: $error_message\n");
	}

	return ($response->content, $elapsed);
	
}

#################
### HTTP POST ###
#################

sub http_post {

	my ($url, $data) = @_;
	
	my $ua = LWP::UserAgent->new('TESTER');
	my $data_debug = join("\n", map { "$_=$data->{$_}" } %$data );
	
	# push @{ $ua->requests_redirectable }, 'POST';

	my $response = eval {
		local $SIG{ALRM} = sub { die("HTTP Post Error\nURL: $url\ERR: Timed Out after 60 seconds\nData:\n$data_debug") };
		alarm 60;
		my $server_reply = $ua->post($url, $data);
		alarm 0;
		return $server_reply;
	};
	
	if ($@) { die("HTTP Post Error\nURL: $url\ERR: $@\nData:\n$data_debug"); }
	
	if ($response->code != 200) {
		my $error_message = $response->content;
		$error_message =~ s/<[a-zA-Z\/][^>]*>//g;
		die("HTTP POST Error\nURL: $url\ERR: $error_message\nData:\n$data_debug");
		exit;
	}

	return $response->content;
	
}


1;