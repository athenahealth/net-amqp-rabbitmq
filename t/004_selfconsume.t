use Test::More tests => 10;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok( 'Net::AMQP::RabbitMQ' );

ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->Connect(
		host => $host,
		user => "guest",
		password => "guest",
	);
} 'connect';

lives_ok {
	$mq->ChannelOpen(
		channel => 1,
	);
} 'channel.open';

lives_ok {
	$mq->ExchangeDeclare(
		channel => 1,
		exchange => 'perl_test_selfconsume',
		exchange_type => 'direct',
	);
} 'exchange.declare';


my $queuename = '';
lives_ok {
	$queuename = $mq->QueueDeclare(
		channel => 1,
		queue => '',
		durable => 1,
		exclusive => 0,
		auto_delete => 1,
	)->queue;
} 'queue.declare';

lives_ok {
	$mq->QueueBind(
		channel => 1,
		queue => $queuename,
		exchange => "perl_test_selfconsume",
		routing_key => "test_q",
	)
} "queue_bind";

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "test_q",
		payload => "Magic Transient Payload",
		exchange => "perl_test_selfconsume",
	);
} 'basic.publish';

my $consumer_tag;
lives_ok {
	$consumer_tag = $mq->BasicConsume(
		channel => 1,
		queue => $queuename,
		consumer_tag => 'ctag',
		no_local => 0,
		no_ack => 1,
		exclusive => 0,
	)->consumer_tag;
} 'basic.consume';

is_deeply(
	{ $mq->Receive() },
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => '23',
			type_id => '2',
			weight => 0,
			payload => '',
			channel => 1,
			class_id => 60,
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
			),
		),
		delivery_frame => Net::AMQP::Frame::Method->new(
			type_id => 1,
			payload => '',
			channel => 1,
			method_frame => Net::AMQP::Protocol::Basic::Deliver->new(
				redelivered => 0,
				delivery_tag => 1,
				routing_key => 'test_q',
				consumer_tag => $consumer_tag,
				exchange => 'perl_test_selfconsume',
			),
		),
		payload => 'Magic Transient Payload',
	},
	'received payload',
);

1;
