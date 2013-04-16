package DemoApp::Auth;

use strict;
use base qw(Exporter);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(auth_verify_token auth_verify_user auth_start_session auth_end_session);

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use DBI;

use LabZero::Fail;
use LabZero::HttpUtils;
use LabZero::Tmojo;

my $db_path;
my $sqlite;
my $last_cleanup = 0;

my $timeout_initial = 60*60*8;
my $timeout_extend = 60*60;

###########################
### auth_verify_token ###
###########################

# USAGE: my $token = auth_verify_user($request);

# Verify that the visitor has a cookie OR Give a cookie and redirect to the /app/Login
# YOU DO NOT NEED TO CALL THIS IF YOU CALL auth_verify_user, but it wont hurt

sub auth_verify_token {

	my ($request) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }

	my $cookie_header = $request->{browser_request}{headers}{Cookie};
	my %cookies = http_parse_cookies($cookie_header);
	my $auth_token = $cookies{'lpc.demoapp.v'};

	if ($auth_token) {
		$request->{browser_request}{auth_token} = $auth_token;
		return $auth_token;
	}

	# If no cookie, give a cookie and kick back to the login page	
	my $ip = $request->{browser_request}{headers}{'X-Real-Ip'};
	my $browser = $request->{browser_request}{headers}{'User-Agent'};
	my $hostname = $request->{browser_request}{headers}{'X-Real-Host'};
	my $token = substr(md5_hex($ip . $browser .time()), 0, 5);
	my $cookie = http_cookie(name => 'lpc.demoapp.v', value => $token, domain => $hostname);
	$request->http_header('Set-Cookie' => $cookie);
	$request->http_redirect($request->{browser_request}{url});

}


#########################
### auth_verify_user ###
#########################

# USAGE: my $user = auth_verify_user($request);

# Verify that the visitor is logged in OR Send user the session expired notice

sub auth_verify_user {

	my ($request) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	
	# Make sure this visitor has a cookie, first
	my $token = auth_verify_token($request);
	
	# Make sure we have a connection
	auth_maintain();
	
	# Now, look for an unexpired session in the database
	
	$sqlite->do('begin immediate transaction');
	my ($id, $user, $expire) = $sqlite->selectrow_array(
		"select id, user, expires_ts from sessions where token=? and expires_ts >= ?",	undef,
		$token,
		time(),
	);
	
	# If we got a user, conditionally extend the session and return that user
	if ($user) {
		my $extend = time() + $timeout_extend;
		if ($extend > $expire) {
			$sqlite->do("update sessions set expires_ts=? where id=?", undef, $extend, $id);
		}
		$sqlite->do('commit');
		$request->{browser_request}{auth_user} = $user;
		return $user;
	}
	
	$sqlite->do('commit');
	
	# If we did not, then return the "your face is expired" code
	my $context = LabZero::Context->load();
	my $tmojo_path = $context->app(DemoApp => 'tmojo_root');
	my $tmojo = LabZero::Tmojo->new(template_dir => $tmojo_path);
	my $html = $tmojo->call('expired.tmo', %{$request->{browser_request}} );
	$request->http_ok($html);

}


# Start a session that marks this visitor's cookie as
# authenticated to the given user's account

sub auth_start_session {

	my ($request, $user) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	if (not $user) { fail('auth_start_session requires a valid username'); }

	# Choose a token based on the visitor cookie
	my $token = auth_verify_token($request); # terminal function wont return if no visitor!
	
	# Make sure we have a connection
	auth_maintain();
	
	$sqlite->do('begin immediate transaction');
	
	# First, check to see if that session already exists and re-use it
	my ($id) = $sqlite->selectrow_array("select id from sessions where token=? and user=?", undef, $token, $user);
	
	if ($id) {
		$sqlite->do("update sessions set created_ts=?, expires_ts=? where id=?", undef,
			time(),
			time() + $timeout_initial,
			$id,
		);
	}
	
	# if not, make the session
	else {
		$sqlite->do("insert into sessions (token, user, created_ts, expires_ts) values (?, ?, ?, ?)", undef,
			$token,
			$user,
			time(),
			time() + $timeout_initial,
		);
		$id = $sqlite->func('last_insert_rowid');
	}
	
	$sqlite->do('commit');
	
	
	
	return $token;
	
}

########################
### auth_end_session ###
########################

sub auth_end_session {

	my ($request) = @_;
	unless ($request) { fail("auth_verify_token requires the request object"); }
	
	# Check for a token
	my $cookie_header = $request->{browser_request}{headers}{Cookie};
	my %cookies = http_parse_cookies($cookie_header);
	my $token = $cookies{'lpc.demoapp.v'};
	if (not $token) {
		print "auth_end_session> no token\n";
		return;
	} # not token, we're done
	
	# Now, look for an unexpired session in the database
	auth_maintain();
	
	$sqlite->do('begin immediate transaction');
	my ($id, $user, $expire) = $sqlite->selectrow_array(
		"select id, user, expires_ts from sessions where token=? and expires_ts >= ?",	undef,
		$token,
		time(),
	);
	
	if (not $user) {
		print "auth_end_session> no user\n";
		$sqlite->do('commit');
		return;
	}

	# If we found a session, delete it
	$sqlite->do("delete from sessions where id=?", undef, $id);
	$sqlite->do('commit');
	print "auth_end_session> deleted session $id\n";

}


sub auth_maintain {

	### INIT THINGS IF NEEDED
	### ONLY ON FIRST CALL
	
	if (not $db_path) {
		my $context = LabZero::Context->load();
		$db_path = $context->app(DemoApp => 'session_db');
		$sqlite = DBI->connect("dbi:SQLite:dbname=$db_path","","");
		$sqlite->{RaiseError} = 1;
		$sqlite->do('begin immediate transaction');
		$sqlite->do("create table if not exists sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, token varchar(255) not null, user varchar(255) not null, expires_ts INT UNSIGNED not null, created_ts INT UNSIGNED not null)");
		$sqlite->do('commit');
	}
	
	### CLEAN UP THE DATABASE IF NEEDED
	### ONLY ONCE PER MINUTE
	
	if ((time() - $last_cleanup) > 60) {
		# later, make this scan for expired sessions and kill them
		$sqlite->do('begin immediate transaction');
		$sqlite->do('delete from sessions where expires_ts < ?', undef, time());
		$sqlite->do('commit');
		$last_cleanup = time();
	}
	
	

}
