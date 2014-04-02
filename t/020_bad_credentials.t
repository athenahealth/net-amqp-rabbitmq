use Test::More tests => 3;
use Test::Exception;

use Time::HiRes qw(gettimeofday tv_interval);

use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ::PP');

ok( my $mq = Net::AMQP::RabbitMQ::PP->new()) ;

local $SIG{ALRM} = sub { die "failed to timeout\n" };

my $attempt = 0.6;
throws_ok {
	# Give a window of 10 seconds for this to run, it should fail in 5.
	alarm 10;
	$mq->connect(
		host => $host,
		username => "guest-asdfasdf",
		password => "guest-asdfasdf",
		timeout => $attempt,
	);
	alarm 0;
} qr/Read error: Connection reset/, "Invalid credentials";
