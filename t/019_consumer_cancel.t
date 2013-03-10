use Test::More tests => 10;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ');


ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->connect(
		host => $host,
		username => "guest",
		password => "guest",
	)
} 'connect';

lives_ok {
	$mq->channel_open(
		channel => 1,
	);
} 'channel.open';

my $queuename = "nr_test_consumer_cancel";
lives_ok {
	$mq->queue_declare(
		channel => 1,
		queue => $queuename,
	);
} 'queue.declare';

my $ctag;
lives_ok {
	$ctag = $mq->basic_consume(
		channel => 1,
		queue => $queuename,
	)->consumer_tag
} 'basic.consume';

my $cancel;
lives_ok {
	$mq->basic_cancel_callback(
		callback => sub {
			my ( %args ) = @_;
			$cancel = \%args;
			die "Got our cancel\n";
		},
	);
} 'basic cancel callback';

lives_ok {
	my $mq2 = Net::AMQP::RabbitMQ->new();
	$mq2->connect( host => $host, username => 'guest', password => 'guest' );

	$mq2->channel_open(
		channel => 2,
	);
	$mq2->queue_delete(
		channel => 2,
		queue => $queuename,
		if_unused => 0,
	);
} 'queue.delete';

# Pretend to wait for a message.
throws_ok {
	$mq->receive(
		method_frame => [ 'Net::AMQP::Protocol::Basic::Cancel' ],
	);
} qr/Got our cancel/, 'canceled';

is_deeply(
	$cancel,
	{
		cancel_frame => Net::AMQP::Frame::Method->new(
			type_id => 1,
			payload => '',
			channel => 1,
			method_frame => Net::AMQP::Protocol::Basic::Cancel->new(
				nowait => 1,
				consumer_tag => $ctag,
			),
		),
	},
	"ctag"
);

1;
