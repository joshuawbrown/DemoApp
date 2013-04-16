package DemoApp::Web::Console;

use strict;

use Data::Dumper;
use POSIX qw(strftime);

use LabZero::Fail;
use LabZero::HttpUtils;
use LabZero::Context;

use DemoApp::Auth;

my $context = LabZero::Context->load();
my $couch = $context->couchdb();
my $tmojo_path = $context->app(DemoApp => 'tmojo_root');
my $tmojo = $context->tmojo($tmojo_path);

### HANDLERS MUST HAVE A METHOD CALLED handle_request to work with the LabZero http_worker
### They can tear off an object if they want, or not.

sub handle_request {

	my ($my_classname, $request) = @_;
	
	# Parse the cookies and make sure we are logged in.
	my $user = auth_verify_user($request);

	my $timeline = $couch->get_view('/demo/_design/bb2/_view/timeline?descending=true');
	my $stuff2 = Dumper($timeline);

	my $html = $tmojo->call('console.tmo', list => $timeline );
	
	$request->http_ok($html);
	
}

1;