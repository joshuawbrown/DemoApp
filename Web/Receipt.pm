package DemoApp::Web::Receipt;

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
	
	# Before we do anything else, verify that we have a tracking cookie
	my $token = auth_verify_token($request);
	my $id;
	
	# First, look in the browser request
	if ($request->{browser_request}{receipt_id}) {
		$id = $request->{browser_request}{receipt_id};
	}
	
	# if it's not there, look in the query
	else {
		my $parsed_query = http_parse_query($request->{browser_request}{query_string});
		$id = $parsed_query->{id};
	}
	
	if ($id) { $id =~ m/a-zA-Z0-9/; }
	
	# tRy to look up the customer rec
	my $query = qq{/demo/_design/bb3/_view/customer_id?descending=true&include_docs=true&key="$id"};
	my $customer = $couch->get_view($query);
	
	# If we failed, try to look it up as a session ID
	if (not scalar(@{$customer->{rows}})) {
		$query = qq{/demo/_design/bb4/_view/session_id?descending=true&include_docs=true&key="$id"};
		$customer = $couch->get_view($query);	
	}
	
	# if we still failed, redirect it over to the other domain
	if (not scalar(@{$customer->{rows}})) {
		$request->http_redirect("http://sales.cinematicprofits.com/receipt/$id");
	}
	
	
	print "> THE STUFF >\n" , Dumper($customer->{rows}[0]{doc}{contact}), "\n";
	
	my $html;
	
	if (scalar(@{$customer->{rows}})) {
		$html = $tmojo->call('receipt.tmo',
			customer => $customer->{rows}[0]{doc},
			id       => $id,
		);
	}
	
	else {
		$html = $tmojo->call('receipt_missing.tmo', id => $id);	
	}
	
	$request->http_ok($html);
	
}

1;