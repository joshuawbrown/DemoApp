package DemoApp::Web::BizzIntegration;

use strict;

use Data::Dumper;

use LabZero::Fail;
use LabZero::HttpUtils;
use LabZero::Context;
use LabZero::Couch;

my $context = LabZero::Context->load();
my $couch = $context->couchdb();

### HANDLES INTEGRATION FROM BIZZBLIZZ STORE

sub handle_request {

	my ($my_classname, $request) = @_;
	
	# Just Grab the msglite request and rebroadcast it over to a deferred handler.
	
	my $context = LabZero::Context->load();
	my $msglite = $context->msg_lite();
	
	my $message = $request->{msglite_msg};
	$msglite->bounce($message, 'lpc.demo.bizzblizz');
	print "* Message bounced to lpc.demo.bizzblizz\n";
	$request->http_defer();

}

1;