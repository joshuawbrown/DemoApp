#!/usr/bin/perl

### LPC SAMPLED CUSTOM MSGLITE WORKER DAEMON ###

# This daemon listens to msglite for incoming web requests that were
# re-directed or initiated by a normal web request. it demonstrates how
# to handle a deferred lower priority request

use strict;

use JSON;
use Data::Dumper;

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

unless ($commands{max_requests}) { $commands{max_requests} = 100; }
unless ($commands{dev_mode})     { $commands{dev_mode} = 0; }

#### GO!

my $context = LabZero::Context->load();
my $glog = $context->glog('demo/deferred');
my $msglite = $context->msg_lite();

# This whole thing is in a closure! how cool is that?

{

	# Safe signal handling
	my $quit = 0;
	$SIG{HUP}  = sub { logger("SIGNAL HUP ($$)"); $quit = 1; };
	$SIG{INT}  = sub { logger("SIGNAL INT ($$)"); $quit = 1; };
	$SIG{QUIT} = sub { logger("SIGNAL QUIT ($$)"); $quit = 1; };
	$SIG{TERM} = sub { logger("SIGNAL TERM ($$)"); $quit = 1; };
	
	# Quit after a fixed number of requests
	my $request_counter = 0;
	my $request_limit = $commands{max_requests};
	
	$glog->(STARTED => "($$) dev_mode=$commands{dev_mode}");
		
	while (!$quit) {
	
		# WAIT FOR THE NEXT AVAILABLE MSG FROM MSGLITE
		my $request_msg = $msglite->ready(1, 'lpc.http_worker');
		next if !defined($request_msg);
		
		# IF QUIT BECAME TRUE WHILE WE WERE WAITING, RE-QUEUE THE MESSAGE AND QUIT
		if ($quit) {
			$msglite->send($request_msg);
			last;
		}
		
		# IN DEV MODE, RESTART IF WE ALREADY HANDLED A REQUEST
		if ($commands{dev_mode} and ($request_counter > 0)) {
			$msglite->send($request_msg);
			$glog->(RESTARTING => "($$) for dev mode");
			last;
		}
		
		#### Parse this message, handle the request
		my $request_string = '-';
		
		# REQUIRE THE HANDLER PACKAGE IN TIS OWN EVAL BUT INSIDE THE LOOP, SO THAT THE
		# DAEMON DIES AND LOGS THE ERROR BUT DOESN'T MAKE UPSTART GIVE UP ON IT IF IT'S
		# HOPELESSLY BUSTED!
		
		if (not $handler_loaded) { # only try this once
		
			if ($commands{handler} !~ m/\w+::\w+/) {
				fail("Failed to specify a valid perl module!\nUsage: http_worker.pl [worker_id] [production(0|1)] [handler_package_name]",
				 		 "Specified handler: $commands{handler}");
			}
			
			else {
				# Manually convert to a package name, then eval it.
				my $package_path = $commands{handler};
				$package_path =~ s{::}{/}g;
				$package_path .= '.pm';
				eval { require $package_path };
				if ($@) {
					# If our handler failed, make a note of it
					warn($@);
					$handler_failed = 1;
				}
				else {
					# If it worked, mark it as done so we dont do it again
				 $handler_loaded = 1;
				}
			}
		
		}
		
		### CALL THE HANDLER IN an EVAL FOR FRIENDLIER ERRORS
		
		my ($status_code, $headers, $body) = eval {
		
			my $browser_request = decode_json($request_msg->body);
			$request_string = "$browser_request->{method} $browser_request->{url}";
			
			my $body_msg = $msglite->ready(10, $browser_request->{'bodyAddr'});
			$browser_request->{body} = $body_msg->{body};
			$browser_request->{timeout} = $body_msg->{timeout};
			
			# if the handler failed to load (earlier), just bail out here
			if ($handler_failed) {
				return ('500', ['Content-Type' => 'text/html'], retro_error_c64(500, 'Main Handler failed compliation (W101)', $commands{handler}));
			}
			
			# Invoke the handler
			
			my $handler_request = LabZero::RequestObject->new($browser_request);
			my $return_body;
			my ($return_status, $return_headers) = $handler_request->execute_handler($commands{handler}, \$return_body);

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
			$body = retro_error_c64(500, 'Request Handler failed  (W102)', $commands{handler});
		}
		
		# Failed to generated HTTP status code
		elsif (not $status_code) {
			$notation = " - No HTTP status code from Handler '$commands{handler}'";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_c64(500, 'No HTTP Status code from handler  (W103)', $commands{handler});
		}
		
		# Failed to generate a header
		elsif ((ref($headers) ne 'ARRAY') or (not scalar(@$headers))) {
			l$notation = " - No valid HTTP header from Handler '$commands{handler}'";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_c64(500, 'No valid HTTP header from handler  (W104)', $commands{handler});
		}		

		### Send the output back to nginx
		$reply = ["$status_code", $headers];
		$encoded_reply = encode_json($reply);
		
		# Success - Dev mode logging
		if ($commands{dev_mode} or $notation) { logger("$status_code $request_string $encoded_reply$notation"); }
		
		# Success - Standard logging
		else { logger("$status_code $request_string"); }
		
		$msglite->send($encoded_reply, 10, $request_msg->reply_addr);
		if ($body ne '') { $msglite->send($body, 10, $request_msg->reply_addr); }
		$msglite->send('', 10, $request_msg->reply_addr);
		
		# Increment the request counter
		$request_counter += 1;
		if ($request_counter >= $request_limit) {
			logger("limit reached ($$): $request_counter requests");
			$quit = 1;
		}
	}
	
	logger("TERMINATED ($$)");
	
}

1;