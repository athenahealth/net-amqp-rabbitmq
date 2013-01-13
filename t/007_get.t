use Test::More tests => 14;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ::Perl');

ok( my $mq = Net::RabbitMQ::Perl->new() );

lives_ok {
	$mq->Connect(
		host => $host,
		username => "guest",
		password => "guest",
	);
} "connect";

lives_ok {
	$mq->ChannelOpen(
		channel => 1,
	);
} "channel.open";

my $queuename = '';
lives_ok {
	$queuename = $mq->QueueDeclare(
		channel => 1,
		queue => '',
		durable => 0,
		exclusive => 0,
		auto_delete => 1,
	)->queue;
} "queue.declare";

lives_ok {
	$mq->QueueBind(
		channel => 1,
		queue => $queuename,
		exchange => "nr_test_x",
		routing_key => "nr_test_q",
	);
} "queue.bind";

my %getr;
lives_ok {
	%getr = $mq->BasicGet(
		channel => 1,
		queue => $queuename,
	);
} "get";

is_deeply( \%getr, {}, "get should return empty" );

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "nr_test_q",
		payload => "Magic Transient Payload",
		exchange => "nr_test_x",
	);
} "basic.publish";

lives_ok {
	%getr = $mq->BasicGet(
		channel => 1,
		queue => $queuename,
	);
} "basic.get";

is_deeply(
	{ %getr },
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => 23,
			weight => 0,
			payload => '',
			type_id => 2,
			class_id => 60,
			channel => 1,
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
			),
		),
		payload => 'Magic Transient Payload',
	},
	"get should see message"
);

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "nr_test_q",
		payload => "Magic Transient Payload 2",
		exchange => "nr_test_x",
		correlation_id => '123',
		reply_to => 'somequeue',
		expiration => 60000,
		message_id => 'ABC',
		type => 'notmytype',
		user_id => 'guest',
		app_id => 'idd',
		delivery_mode => 1,
		priority => 2,
		timestamp => 1271857990,
	);
} 'basic.publish';

lives_ok {
	%getr = $mq->BasicGet(
		channel => 1,
		queue => $queuename,
	);
} "get";

is_deeply(
	{ %getr },
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => 25,
			weight => 0,
			payload => '',
			type_id => 2,
			class_id => 60,
			channel => 1,
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
			),
		),
		payload => 'Magic Transient Payload 2',
	},
	"get should see message"
);

1;
