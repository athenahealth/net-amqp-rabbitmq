use Test::More tests => 5;
use Test::Exception;

use strict;
use warnings;

SKIP: {
	my $can_test = eval { require Socket::Linux };
	skip "Keepalive dependencies missing", 5 unless $can_test;

	my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

	use_ok('Net::AMQP::RabbitMQ::PP');

	ok( my $mq = Net::AMQP::RabbitMQ::PP->new() );

	lives_ok {
		$mq->connect(
			host => $host,
			username => "guest",
			password => "guest",
		);
	} 'connect';

	lives_ok {
		$mq->set_keepalive(
			count => 1,
			interval => 2,
			idle => 2,
		);
	} 'keep_alive';

	sleep 10;

	lives_ok {
		$mq->channel_open(
			channel => 1,
		);
	};
}

1;
