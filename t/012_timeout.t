use Test::More tests => 5;
use Test::Exception;

use Time::HiRes qw(gettimeofday tv_interval);

use strict;
use warnings;


use_ok('Net::AMQP::RabbitMQ::PP');

ok( my $mq = Net::AMQP::RabbitMQ::PP->new()) ;

local $SIG{ALRM} = sub { die "failed to timeout\n" };

my $start = [gettimeofday];
my $attempt = 0.6;
eval {
	# Give a window of 10 seconds for this to run, it should fail in 5.
	alarm 10;
	$mq->connect(
		# google.com:81 drops packets, hooray.
		host => 'www.google.com',
		port => 81,
		username => "guest",
		password => "guest",
		timeout => $attempt,
	);
	alarm 0;
};

my $duration = tv_interval($start);
isnt($@, "failed to timeout\n", "failed to timeout");
isnt($@, '', "connect");

# give a bit of tolerance for the timeout.
cmp_ok( abs( $duration - $attempt ), '<', 1, 'timeout' );
