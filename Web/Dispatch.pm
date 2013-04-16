package DemoApp::Web::Dispatch;

use strict;

use Data::Dumper;

use LabZero::Fail;
use LabZero::RetroHTML;

#####################
### CONFIGURATION ###
#####################

my $context = LabZero::Context->load();

# This is the PERL handler prefix, IE, the namespace for this application itself
# Having it as a var makes it easier to clone and fork this app
my $lib_prefix  = 'DemoApp::Web';

# This is the PERL handler root path, for filesystem 'exists' checks
# It has to match your $lib_prefix
my $lib_root  = $context->app(DemoApp => 'lib_root'); # '/home/zero/app/lib/DemoApp/Web';

# This is the URL prefix for the app. IE: http://foo.com/$code_suburl/handler
my $code_suburl = $context->app(DemoApp => 'app_prefix'); # 'app';

# This is the list of restricted handlers that MAY NOT be called
my %restricted = (
	Dispatch => 1,
);

my $use_exceptions = 0;

# Our own cached list of loaded packages
my %loaded;

### HANDLERS MUST HAVE A METHOD CALLED handle_request to work with the LabZero http_worker
### They can tear off an object if they want, or not. This one does not.

##############################################
### THIS MAIN HANDLER SIMPLY DOES DISPATCH ###
### TO APPROPRIATE LIBRARIES BASED ON THE  ###
### NAME SPACE OF THE URL AND THE PACKAGES ###
##############################################

sub handle_request {

	my ($my_classname, $request) = @_;
	
	my $url = $request->{browser_request}{url};
	my ($path, $query);
	if ($url =~ m{^([^?]+)\?(.+)}) { $path = $1; $query = $2; }
	else { $path = $url; $query = ''; }

	my $handler_name;
	
	### First, we only accept GET or POST
	my $method = $request->{browser_request}{'method'};
	if ($method !~ m/^(GET|POST)$/) {
		$request->http_err(403, retro_error_c64(403, "METHOD '$method' NOT SUPPORTED (D101)", $path));
	}
	
	### ATTEMPT TO IDENTIFY APPLICATION REQUESTS ###
	# Generally, NGINX will only send us valid requests, but you never know
	
	# (1) See if this matches a valid looking handler path
	if ($path =~ m{^/$code_suburl}) {
		if ($path =~ m{^/$code_suburl/(\w+)$}) { $handler_name = $1; }
		else {
			print("* FAILED HANDLER LOOKUP: $path\n");
			$request->http_err(400, retro_error_c64(400, 'invalid request (D102)', $path));
		}
	}
		
	elsif ($path =~ m{^/receipt/([a-zA-Z0-9]+)$}) {
		$handler_name = 'Receipt';
		$request->{browser_request}{receipt_id} = $1;
	} 
	
	### APPLICATION HANDLER SPACE ###
	
	if ($handler_name) {
	
		# Reject Restricted Names
		if ($restricted{$handler_name}) {
			$request->http_err(403, retro_error_c64(403, 'URL NOT ALLOWED (D103)', $path));
		}
		
		# Reject restricted names
		elsif (($handler_name !~ m/[a-z]/) or ($handler_name !~ m/[A-Z]/)) {
			$request->http_err(403, retro_error_c64(403, 'URL NOT ALLOWED (D104)', $path));
		}

		# Looks valid, invoke the handler!
		else {
			my $lib_name = use_handler($handler_name, $request); # This will fail if that handler doesn't exist
			
			# Put our extra goodies into the request
			$request->{browser_request}{handler_path}  = $path;
			$request->{browser_request}{query_string} = $query;
			$request->{browser_request}{app_path}     = '/' . $code_suburl;
			
			$lib_name->handle_request($request); # This will fail if that handler is broken
			
			return; # The line above SHOULD never return to us, so if we get here it's failure-time
			
		}
	}
	
	### FAILURE
	
	$request->http_err(403, retro_error_c64(403, 'URL not supported (D105)', $path));
	
	# $request->http_send_file_accel($html_root . $path);

}

### MAP EXCEPTIONS TO THEIR OWN HANDLERS ###

sub handle_exceptions {

	my ($path) = @_;
	
	# No exceptions for now! Add this later!
	return '';

}

sub use_handler {

	my ($libname, $request) = @_;
	
	my $perl_lib = $lib_prefix . '::' . $libname;
	
	# Skip it if we already loaded it
	if ($loaded{$perl_lib}) { return $perl_lib; }
	
	# Look at the filesystem to see if it exists - simple check
	my $file_path = $lib_root . '/' . $libname . '.pm';
	if (not -e $file_path) {
		$request->http_err(404, retro_error_c64(404, 'HANDLER DOES NOT EXIST (D201)', $libname));
	}
	
	# try to load it. fail if it didnt work and request that the daemon terminate
	eval{ require $file_path };
	if ($@) {
		fret($@, $perl_lib);
		$request->http_fatal_err(500, retro_error_c64(500, 'HANDLER FAILED TO LOAD (D202)', $libname));
	}	
	
	# Now make sure the package exists and actually has a handler
	if (not $perl_lib->can('handle_request')) {
		$request->http_fatal_err(500, retro_error_c64(500, 'HANDLER DOES NOT SUPORT handle_request (D203)', $libname));
	}
	
	# if it worked, note that it worked and return
	$loaded{$perl_lib} = 1;
	
	return($perl_lib);
	
}



1;