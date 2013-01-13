use Test::More tests => 17;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ::Perl');

ok( my $mq = Net::RabbitMQ::Perl->new() );

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
	)
} 'channel.open';

lives_ok {
	$mq->QueueDeclare(
		channel => 1,
		queue => "nr_test_ack",
		passive => 0,
		durable => 1,
		exclusive => 0,
		auto_delete => 0,
	);
} "queue_declare";

lives_ok {
	$mq->QueueBind(
		channel => 1,
		queue => "nr_test_ack",
		exchange => "nr_test_x",
		routing_key => "nr_test_ack_route"
	);
} "queue_bind";

lives_ok {
	$mq->QueuePurge(
		channel => 1,
		queue => "nr_test_ack",
	);
} 'queue.purge';

my $payload = "Magic Payload $$";

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "nr_test_ack_route",
		payload => $payload,
		exchange => "nr_test_x",
	);
} "basic.publish";

my $consumer_tag;
lives_ok {
	$consumer_tag = $mq->BasicConsume(
		channel => 1,
		queue => "nr_test_ack",
		no_ack => 0,
		consumer_tag => 'ctag',
	)->consumer_tag;
} "basic.consume";

is_deeply(
	{ $mq->Receive() },
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => length $payload,
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
				routing_key => 'nr_test_ack_route',
				consumer_tag => $consumer_tag,
				exchange => 'nr_test_x',
			),
		),
		payload => $payload,
	},
	'received payload',
);

lives_ok {
	$mq->Disconnect();
} "disconnect";

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

lives_ok {
	$consumer_tag = $mq->BasicConsume(
		channel => 1,
		queue => "nr_test_ack",
		no_ack => 0,
		consumer_tag =>
		'ctag',
	)->consumer_tag;
} 'basic.consume';

is_deeply(
	{ my %message = $mq->Receive() },
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => length $payload,
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
				redelivered => 1,
				delivery_tag => 1,
				routing_key => 'nr_test_ack_route',
				consumer_tag => $consumer_tag,
				exchange => 'nr_test_x',
			),
		),
		payload => $payload,
	},
	"payload"
);

lives_ok {
	$mq->BasicAck(
		channel => 1,
		delivery_tag => $message{delivery_frame}->method_frame->delivery_tag,
	);
} 'basic.ack';

lives_ok {
	$mq->Disconnect();
} "disconnect";


1;
