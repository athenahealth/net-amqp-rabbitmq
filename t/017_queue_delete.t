use Test::More tests => 6;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ');

ok( my $mq = Net::AMQP::RabbitMQ->new(), 'new' );

lives_ok {
	$mq->Connect(
		host => $host,
		username => "guest",
		password => "guest",
	);
} 'connect';

lives_ok {
	$mq->ChannelOpen(
		channel => 1,
	);
} 'channel.open';

my $queue = '';
lives_ok {
	$queue = $mq->QueueDeclare(
		channel => 1,
		durable => 1,
		exclusive => 0,
		auto_delete => 0,
	)->queue;
} 'queue.declare';

lives_ok {
	$mq->QueueDelete(
		channel => 1,
		queue => $queue,
		if_empty => 1,
		if_unused => 1,
	);
} 'queue.delete';

1;
