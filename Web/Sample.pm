package DemoApp::Web::Sample;

use strict;

use Data::Dumper;

use LabZero::Fail;
use LabZero::HttpUtils;
use LabZero::Tmojo;

my $context = LabZero::Context->load();
my $tmojo_path = $context->app(DemoApp => 'tmojo_root');
my $tmojo = $context->tmojo($tmojo_path);

### HANDLERS MUST HAVE A METHOD CALLED handle_request to work with the LabZero http_worker
### They can tear off an object if they want, or not.

sub handle_request {

	my ($my_classname, $request) = @_;
	
	# Render using tmojo
	my $html = $tmojo->call('console.tmo', %{$request->{browser_request}} );
	my $html = time();

	my $stuff = Dumper($request->{browser_request});
	
	print "* MANUEL IS THE SHIT\n";
	$request->http_ok($html);


}

1;