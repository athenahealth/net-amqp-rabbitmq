use Test::More tests => 13;
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
} "connect";

lives_ok {
	$mq->channel_open(
		channel => 1,
	);
} "channel_open";

my $delete = 1;
my $key = 'key';
my $queue;
lives_ok {
	$queue = $mq->queue_declare(
		channel => 1,
		queue => "",
		auto_delete => $delete,
	)->queue;
} "queue_declare";

my $exchange = "perl-x-$queue";
lives_ok {
	$mq->exchange_declare(
		channel => 1,
		exchange => $exchange,
		exchange_type => 'headers',
		auto_delete => $delete,
	);
} "exchange_declare";

my $headers = { foo => 'bar' };
lives_ok {
	$mq->queue_bind(
		channel => 1,
		queue => $queue,
		exchange => $exchange,
		routing_key => $key,
		headers => $headers,
	);
} "queue_bind";

# This message doesn't have the correct headers so will not be routed to the queue
lives_ok {
	$mq->basic_publish(
		channel => 1,
		routing_key => $key,
		payload => "Unroutable",
		exchange => $exchange,
	)
} "publish unroutable message";

lives_ok {
	$mq->basic_publish(
		channel => 1,
		routing_key => $key,
		payload => "Routable",
		exchange => $exchange,
		props => {
			headers => $headers,
		},
	);
} "publish routable message";

my $ctag;
lives_ok {
	$ctag = $mq->basic_consume(
		channel => 1,
		queue => $queue,
	)->consumer_tag;
} "consume";

my $msg;
is_deeply(
	$msg = $mq->receive(),
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => 8,
			type_id => 2,
			weight => 0,
			payload => '',
			class_id => 60,
			channel => 1,
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
				headers => {
					foo => 'bar',
				},
			),
		),
		payload => 'Routable',
		delivery_frame => Net::AMQP::Frame::Method->new(
			type_id => 1,
			payload => '',
			channel => 1,
			method_frame => Net::AMQP::Protocol::Basic::Deliver->new(
				redelivered => 0,
				delivery_tag => 1,
				routing_key => 'key',
				consumer_tag => $ctag,
				exchange => $exchange,
			),
		),
	},
	"Got expected message",
);

throws_ok {
	# We get our channel closed when this fails, so lets open a new one.
	$mq->channel_open(
		channel => 2
	);

	$mq->queue_unbind(
		channel => 2,
		queue => $queue,
		exchange => $exchange,
		routing_key => $key,
	)
} qr/NOT_FOUND - no binding /, "Unbinding queue fails without specifying headers";

lives_ok {
	$mq->queue_unbind(
		channel => 1,
		queue => $queue,
		exchange => $exchange,
		routing_key => $key,
		headers => $headers,
	);
} "queue_unbind";

1;
