use Test::More tests => 8;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok( 'Net::AMQP::RabbitMQ' );

ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->connect(
		host => $host,
		username => "guest",
		password => "guest",
	);
} "connect";

lives_ok {
	$mq->channel_open(
		channel => 1,
	);
} "channel.open";

lives_ok {
	$mq->channel_open(
		channel => 2,
	);
} "channel.open";

my $testqueue;
lives_ok {
	$testqueue = $mq->queue_declare(
		channel => 1,
		passive => 0,
		durable => 0,
		exclusive => 0,
		auto_delete => 1,
	)->queue;
} 'queue.declare';

lives_ok {
	$mq->basic_consume(
		channel => 1,
		queue => $testqueue,
		exclusive => 1,
	);
} 'basic.consume';

throws_ok {
	$mq->basic_consume(
		channel => 2,
		queue => $testqueue,
		exclusive => 1,
	);
} qr/Channel 2 closed ACCESS_REFUSED/, 'basic.consume';

1;
