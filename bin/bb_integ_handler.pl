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
use LabZero::Couch;
use LabZero::HttpUtils;
use LabZero::RetroHTML;

my $context = LabZero::Context->load();
my $couch = $context->couchdb();

$| = 1;

############
## USAGE ###
############

# sample_delayed_handler.pl

########################
### HANDLER SETTINGS ###
########################

my $address = 'lpc.demo.bizzblizz'; # Look here for messages

my %integ_map = (
	integrazzle => {
		url => 'http://cinematicprofits.com/api/products.php',
		code => 'cinematic_profits',
	},

	a => {
		url => 'http://cinematicprofits.com/api/products.php',
		code => 'cinematic_profits',
	},
	
		b => {
		url => 'http://cinematicprofits.com/api/products.php',
		code => 'unlimited_license',
	},
	
		c => {
		url => 'http://movietwitts.com/api/products.php',
		code => 'twitter_traffic',
	},
	
		d => {
		url => 'http://cinematicprofits.com/api/products.php',
		code => 'facebook_training',
	},
	
);

my @words = qw(movie video cash win awesome tech edit blog style solid fast quick genius max cool lifestyle whiz tech firepower niche profits results wealth amazing crafty smart research bliss ace integrity freedom success);

######################
#### ARGV SETTINGS ###
######################

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
		my $request_msg = $msglite->ready(1, $address);
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
			$body = retro_error_simple(500, 'Request Handler failed  (B101)', $commands{handler});
		}
		
		# Failed to generated HTTP status code
		elsif (not $status_code) {
			$notation = " - No HTTP status code from Handler '$commands{handler}'";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_simple(500, 'No HTTP Status code from handler  (B102)', $commands{handler});
		}
		
		# Failed to generate a header
		elsif ((ref($headers) ne 'ARRAY') or (not scalar(@$headers))) {
			$notation = " - No valid HTTP header from Handler '$commands{handler}'";
			$status_code = '500';
			$headers = ['Content-Type' => 'text/html'];
			$body = retro_error_simple(500, 'No valid HTTP header from handler  (B103)', $commands{handler});
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

	my $method = $browser_request->{'method'};
	if ($method !~ m/^(POST)$/) {
		return(403, $headers, retro_error_simple(403, "Method '$method' not supported", 'B201'));
	}
		
	# Get the POST body. if it's missing, fail.
	my $msglite_post = $msglite->ready(2, $browser_request->{bodyAddr});
	unless($msglite_post) { fail("Failed to get HTTP POST BODY", $request_msg); }
	
	# Decode the post or die
	my $decoded_post = http_parse_query($msglite_post->{body});
	unless($decoded_post->{refId}) { fail("Malformed POST", $msglite_post->{body}); }
	my $ref_id = $decoded_post->{refId}; # The important integration!
	
	# Decode the customer or die	
	my $customer = decode_json($decoded_post->{customer});
	unless($customer->{details}) { fail("Missing refId", $msglite_post->{body}); }
	
	# Find the target buyer contact
	my $order_id;
	my $contact;
	my $target_detail;
	my $date_stamp;
	my $customer_id = $customer->{'_id'};
	
	foreach my $detail (@{$customer->{details}}) {
		if ($detail->{id} eq $ref_id) {
			print "DETAIL: ", Dumper($detail), "\n";
			$order_id   = $detail->{orderId};
			$contact    = $detail->{contact};
			$date_stamp = $detail->{when};
			$target_detail = $detail;
			last;
		}
	}
	
	unless ($order_id) { fail("Missing orderId in details", $target_detail); }
	unless ($contact->{email}) { fail("Missing contact:email in details", $target_detail); }
	
	# Find the target order item
	foreach my $detail (@{$customer->{details}}) {
		if (($detail->{type} eq 'order') and ($detail->{id} eq $order_id)) {
			print "ORDER: ", Dumper($detail), "\n";
			# integrate each item in the list
			foreach my $item (@{$detail->{items}}) {
				my $product = lc($item->{productName});
				my $price = $item->{price} + 0;
				do_integration($customer_id, $ref_id, $order_id, $date_stamp, $contact, $product, $price);
			}
			last;
		}
	}
	
	# print "CUSTOMER> " , Dumper($customer), "\n\n";
	
	
	
	# Not return a friendly message of happiness
	my $stamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
	return('200', $headers, $stamp);
	
}

sub do_integration {

	my ($customer_id, $ref_id, $order_id, $date_stamp, $contact, $product, $price) = @_;
	
	my $hack = lc(substr($contact->{firstName}, 0, 1));
	if ($integ_map{$hack}) { $product = $hack; }
	
	# See if this customer already exists
	# handle this later
	
	# Save this integration into COUCH
	
	my %record = (
		customer_id => $customer_id,
		type     => 'bb_integration',
		contact  => $contact,
		history  => [{
			status   => 'pending',
			ref_id   => $ref_id,
			order_id => $order_id,
			product  => $product,
			price    => $price,
		}],
	);
	
	my $couch = $context->couchdb();
	
	my $doccy = $couch->new_doc('demo' => \%record);
	print "* Saved record ID $doccy\n";
	
	# Find the product or fail
	if (not $integ_map{$product}) {
		fail("Unrecognized product: $product", $product);
	}
	
	# Generate a password
	my $word = $words[int(rand(scalar(@words)))];
	my $int = 50 + int(rand(950));
	my $password = lc(substr($contact->{firstName}, 0,1)) . lc(substr($contact->{lastName}, 0,1)) . $int . $word;
	
	my $result = $couch->update_doc(demo => $doccy, sub { $_[0]->{password} = $password; });
	
	# Post to the target URL with the given stuffs
	
	my %post_content = (
		action        => 'purchase',
		product       => $integ_map{$product}{code},
		amount        => $price,
		customer_id   => $customer_id,
		email         => $contact->{email},
		password      => $password,
		first_name    => $contact->{firstName},
		last_name     => $contact->{lastName},
		purchase_date => $date_stamp,
	);
	print ">POSTING: ", Dumper(\%post_content), "\n\n";
	
	my ($code, $elapsed, $content) = http_post($integ_map{$product}{url}, \%post_content);
	print "> $code ($elapsed)\n$content\n\n";
	
	my $status;
	if ($code == 200) { $status = 'complete'; }
	else { $status = 'error'; }

	print "
status  => $status\n
code    => $code\n
content => $content\n
elapsed => $elapsed
";
	
	my $result = $couch->update_doc(demo => $doccy, sub {
		$_[0]->{history}[-1]{status} = $status;
		$_[0]->{history}[-1]{result} = {
		 code    => $code,
		 content => $content,
		 elapsed => $elapsed,
		};
	});
	
	print "UPDATE> ", Dumper($result), "\n";
	
}

1;