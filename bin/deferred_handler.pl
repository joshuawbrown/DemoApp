#!/usr/bin/perl

### LPC SAMPLE DEFERRED MSGLITE HANDLER ###

# This daemon listens to msglite for incoming web requests that were
# re-directed or initiated by a normal web request. it demonstrates how
# to handle a deferred lower priority request

use strict;

use JSON;
use Data::Dumper;
use POSIX qw(strftime);

use LabZero::Context;
use LabZero::Fail;
use LabZero::RetroHTML;

$| = 1;

############
## USAGE ###
############

# sample_delayed_handler.pl


#### PARSE SETTINGS ###

my %commands;
foreach my $arg (@ARGV) {
	if ($arg =~ m/^([a-zA-Z_]+)=(.+)/) { $commands{$1} = $2; }
}

# 

unless ($commands{max_requests}) { $commands{max_requests} = 100; }
unless ($commands{dev_mode})     { $commands{dev_mode} = 0; }

##################################################
#### THIS LOOP IS JUST TEMPLATE HANDLER CODE   ###      
#### THE ACTUAL STUFF IS HANDLED BY do_request ###
##################################################

my $context = LabZero::Context->load();
my $glog = $context->glog('demo/deferred');
my $msglite = $context->msg_lite();

# This whole thing is in a closure! how cool is that?

{

	# Safe signal handling
	my $quit = 0;
	$SIG{HUP}  = sub { logger(SIGNAL => "HUP ($$)"); $quit = 1; };
	$SIG{INT}  = sub { logger(SIGNAL => "INT ($$)"); $quit = 1; };
	$SIG{QUIT} = sub { logger(SIGNAL => "QUIT ($$)"); $quit = 1; };
	$SIG{TERM} = sub { logger(SIGNAL => "TERM ($$)"); $quit = 1; };
	
	# Quit after a fixed number of requests
	my $request_counter = 0;
	my $request_limit = $commands{max_requests};
	
	logger(STARTED => "($$) dev_mode=$commands{dev_mode}");
		
	while (!$quit) {
	
		# WAIT FOR THE NEXT AVAILABLE MSG FROM MSGLITE
		my $request_msg = $msglite->ready(1, 'lpc.demo.deferred');
		next if !defined($request_msg);
		
		# IF QUIT BECAME TRUE WHILE WE WERE WAITING, RE-QUEUE THE MESSAGE AND QUIT
		if ($quit) {
			$msglite->send($request_msg);
			last;
		}
		
		# IN DEV MODE, RESTART IF WE ALREADY HANDLED A REQUEST
		if ($commands{dev_mode} and ($request_counter > 0)) {
			$msglite->send($request_msg);
			logger(RESTARTING => "($$) for dev mode");
			last;
		}
				
		### CALL THE HANDLER IN an EVAL FOR FRIENDLIER ERRORS
		
		my $request_string = '-';
		
		my ($status_code, $headers, $body) = eval {
		
			# Decode the JSON of the message body here for nice logging.
			my $browser_request = decode_json($request_msg->body);
			$request_string = "$browser_request->{method} $browser_request->{url}";
			
			# Invoke our handler subroutine 
			my ($return_status, $return_headers, $return_body) = do_request($browser_request, $request_msg);

			# Return the results
			return ($return_status, $return_headers, $return_body);
			
		};
										
		# Handle errors and log any STDERR stuff
		
		my ($reply, $encoded_reply, $notation);
			
		# Internal error
		if ($@) {
			$notation = " - Handler '$commands{handler}' failed\n$@";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_c64(500, 'Request Handler failed  (D102)', $commands{handler});
		}
		
		# Failed to generated HTTP status code
		elsif (not $status_code) {
			$notation = " - No HTTP status code from Handler '$commands{handler}'";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_c64(500, 'No HTTP Status code from handler  (D103)', $commands{handler});
		}
		
		# Failed to generate a header
		elsif ((ref($headers) ne 'ARRAY') or (not scalar(@$headers))) {
			l$notation = " - No valid HTTP header from Handler '$commands{handler}'";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_c64(500, 'No valid HTTP header from handler  (D104)', $commands{handler});
		}		

		### Send the output back to nginx
		$reply = ["$status_code", $headers];
		$encoded_reply = encode_json($reply);
		
		# Success - Dev mode logging
		if ($commands{dev_mode} or $notation) { logger($status_code => "$request_string $encoded_reply$notation"); }
		
		# Success - Standard logging
		else { logger($status_code => "$request_string"); }
		
		$msglite->send($encoded_reply, 10, $request_msg->reply_addr);
		if ($body ne '') { $msglite->send($body, 10, $request_msg->reply_addr); }
		$msglite->send('', 10, $request_msg->reply_addr);
		
		# Increment the request counter
		$request_counter += 1;
		if ($request_counter >= $request_limit) {
			logger(QUITTING => "limit reached ($$): $request_counter requests");
			$quit = 1;
		}
	}
	
	logger(TERMINATED => "Process $$");
	
}

#########################################
### LOGGER WILL JUST PASS OFF TO GLOG ###
### IN THIS VERSION IT JUST PRINTS    ###
#########################################

sub logger {

	my ($event, $description) = @_;
	{
		local $| = 1;
		print "$event: $description\n";
	}

}


#############################################
### do_request IS THE ACTUAL HANDLER CODE ###
#############################################

sub do_request {

	my ($browser_request, $request_msg) = @_;
	
	my $headers = ['Content-Type', 'text/html; charset=UTF-8'];
	# sleep(1);
	my $stamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
	return('200', $headers, $stamp);
	
}


1;