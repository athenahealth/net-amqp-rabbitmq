use Test::More tests => 6;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ');

ok( my $mq = Net::AMQP::RabbitMQ->new(), "Created object" );

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

my $delete = 1;
my $queue = "x-headers-" . rand();

lives_ok {
	$queue = $mq->queue_declare(
		channel => 1,
		queue => $queue,
		auto_delete => $delete,
		expires => 60000,
	)->queue;
} "queue_declare";

throws_ok {
	$queue = $mq->queue_declare(
		channel => 1,
		queue => $queue,
		auto_delete => $delete,
	);
} qr/PRECONDITION_FAILED/, "Redeclaring queue without header arguments fails.";
