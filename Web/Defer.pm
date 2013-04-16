package DemoApp::Web::Defer;

use strict;

use Data::Dumper;

use LabZero::Fail;
use LabZero::HttpUtils;
use LabZero::Context;

### HANDLERS MUST HAVE A METHOD CALLED handle_request to work with the LabZero http_worker
### They can tear off an object if they want, or not.

sub handle_request {

	my ($my_classname, $request) = @_;
	
	# Grab the msglite request and rebroadcast it over to the deferred request handler.
	
	my $context = LabZero::Context->load();
	my $msglite = $context->msg_lite();
	
	my $message = $request->{msglite_msg};
	$msglite->bounce($message, 'lpc.demo.deferred');
	$request->http_defer();

}

1;