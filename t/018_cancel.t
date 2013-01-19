use Test::More tests => 7;
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

my $queue;
lives_ok {
	$queue = $mq->QueueDeclare(
		channel => 1,
	)->queue;
} 'queue.declare';

my $ctag;
lives_ok {
	$ctag = $mq->BasicConsume(
		channel => 1,
		queue => $queue,
		consumer_tag => 'ctag',
	);
} 'basic.consume';

lives_ok {
	$mq->BasicCancel(
		channel => 1,
		consumer_tag => $ctag,
	);
} 'basic.cancel';

1;
