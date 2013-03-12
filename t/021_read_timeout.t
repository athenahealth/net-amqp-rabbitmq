use Test::More tests => 8;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok( 'Net::AMQP::RabbitMQ' );

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
} "channel.open";

my $testqueue;
lives_ok {
	$testqueue = $mq->queue_declare(
		channel => 1,
		passive => 0,
		durable => 0,
		exclusive => 0,
		auto_delete => 1,
	)->queue;
} 'queue.declare';

my $consumertag;
lives_ok {
	$consumertag = $mq->basic_consume(
		channel => 1,
		queue => $testqueue,
		consumer_tag => 'ctag',
		no_local => 0,
		no_ack => 1,
		exclusive => 0,
	)->consumer_tag;
} "consume";

my $rv;
lives_ok {
	local $SIG{ALRM} = sub {
		die "Timeout";
	};
	alarm 5;
	$rv = $mq->receive(
		timeout => 1.5,
	);
	alarm 0;
} "recv";

is_deeply(
	$rv,
	undef,
);

1;
