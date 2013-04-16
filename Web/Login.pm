package DemoApp::Web::Login;

use strict;

use Data::Dumper;

use LabZero::Fail;
use LabZero::HttpUtils;
use LabZero::Tmojo;

use DemoApp::Auth;

### HANDLERS MUST HAVE A METHOD CALLED handle_request to work with the LabZero http_worker
### They can tear off an object if they want, or not.

my $context = LabZero::Context->load();
my $tmojo_path = $context->app(DemoApp => 'tmojo_root');
my $tmojo = $context->tmojo($tmojo_path);

sub handle_request {

	my ($my_classname, $request) = @_;
	
	# Before we do anything else, verify that we have a tracking cookie
	my $token = auth_verify_token($request);
	
	# If we received a GET, then show the login page
	if ($request->{browser_request}{'method'} eq 'GET') {
	
		my $parsed_query = http_parse_query($request->{browser_request}{query_string});
		my $message;
		if ($parsed_query->{command} eq 'logout') {
		  auth_end_session($request);
		  $message = 'Logged Up Outa Here';
		}

		my $html = $tmojo->call('login.tmo',
			message => $message,
			request => $request->{browser_request},
		);
		
		$request->http_ok($html);
	}

	# If we got a post, just get it, log it, and automagically authenticate!
	if ($request->{browser_request}{'method'} eq 'POST') {
		my $post = $request->get_http_body();
		my $decoded_post = http_parse_query($post);
		if (($decoded_post->{username} eq 'bob') and ($decoded_post->{password} eq 'awesome')) {
			auth_start_session($request, 'bobjones');
			$request->http_redirect($request->{browser_request}{app_path} . '/Console');
		}
		else {
			$decoded_post->{username} =~ tr/_a-zA-Z0-9//cd;
			my $html = $tmojo->call('login.tmo',
				message => 'Invalid Login',
				username => $decoded_post->{username}, 
				request => $request->{browser_request},
			);
			$request->http_ok($html);
		}
	}
	

}

1;