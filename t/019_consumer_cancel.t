use Test::More tests => 10;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ');


ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->Connect(
		host => $host,
		username => "guest",
		password => "guest",
	)
} 'connect';

lives_ok {
	$mq->ChannelOpen(
		channel => 1,
	);
} 'channel.open';

my $queuename = "nr_test_consumer_cancel";
lives_ok {
	$mq->QueueDeclare(
		channel => 1,
		queue => $queuename,
	);
} 'queue.declare';

my $ctag;
lives_ok {
	$ctag = $mq->BasicConsume(
		channel => 1,
		queue => $queuename,
	)->consumer_tag
} 'basic.consume';

my $cancel;
lives_ok {
	$mq->BasicCancelCallback(
		callback => sub {
			my ( %args ) = @_;
			$cancel = \%args;
			die "Got our cancel\n";
		},
	);
} 'basic cancel callback';

lives_ok {
	my $mq2 = Net::AMQP::RabbitMQ->new();
	$mq2->Connect( host => $host, username => 'guest', password => 'guest' );

	$mq2->ChannelOpen(
		channel => 2,
	);
	$mq2->QueueDelete(
		channel => 2,
		queue => $queuename,
		if_unused => 0,
	);
} 'queue.delete';

# Pretend to wait for a message.
throws_ok {
	$mq->Receive(
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
