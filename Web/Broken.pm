package DemoApp::Web::Broken;

use strict;

use Data::Dumper;

use LabZero::Fail;
use LabZero::HttpUtils;

### HANDLERS MUST HAVE A METHOD CALLED handle_request to work with the LabZero http_worker
### They can tear off an object if they want, or not.

sub not_handle_request {

	my ($my_classname, $request) = @_;
	
	my $stuff = Dumper($request->{browser_request});
	
	my $cookie = http_cookie(name => 'flavor', value => 'oatmeal', domain => 'lpc.bizzblizz.net');
	
	$request->http_header('Set-Cookie' => $cookie);
	$request->http_ok("<html><body><b>This is what your request looks like:</b><pre>$stuff</pre></body></html>");

}

1;