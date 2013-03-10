use Test::More tests => 6;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ');

ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->connect(
		host => $host,
		username => "guest",
		password => "guest",
	);
} 'connect';

lives_ok {
	$mq->channel_open(
		channel => 1,
	);
};

my $expect_qn = 'test.net.rabbitmq.perl';
my $declareok;
lives_ok {
	$declareok = $mq->queue_declare(
		channel => 1,
		queue => $expect_qn,
		durable => 1,
		exclusive => 0,
		auto_delete => 1,
	); 
} 'queue.declare';

is_deeply(
	$declareok,
	Net::AMQP::Protocol::Queue::DeclareOk->new(
		consumer_count => 0,
		queue => $expect_qn,
		message_count => 0,
	)
);

1;
