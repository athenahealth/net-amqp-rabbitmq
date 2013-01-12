use Test::More tests => 5;
use strict;
use Time::HiRes qw/gettimeofday tv_interval/;

my $host = '199.15.224.0'; # This OmniTI IP will hang
$SIG{'PIPE'} = 'IGNORE';
use_ok('Net::RabbitMQ');

my $mq = Net::RabbitMQ->new();
ok($mq);

local $SIG{ALRM} = sub { die "failed to timeout\n" };

my $start = [gettimeofday];
my $attempt = 0.6;
eval {
	# Give a window of 10 seconds for this to run, it should fail in 5.
	alarm 10;
	$mq->connect($host, {
		user => "guest",
		password => "guest",
		timeout => $attempt
	});
	alarm 0;
};
my $duration = tv_interval($start);
isnt($@, "failed to timeout\n", "failed to timeout");
isnt($@, '', "connect");
# 50ms tolerance should work with most operating systems
cmp_ok(abs($duration-$attempt), '<', 0.05, 'timeout');
