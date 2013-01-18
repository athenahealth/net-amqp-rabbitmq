use Test::More tests => 7;
use Test::Exception;
use strict;
use warnings;

use Time::HiRes;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";
use_ok('Net::AMQP::RabbitMQ');

ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->Connect(
		host => $host,
		username => "guest",
		password => "guest",
		heartbeat => 1,
	);
} 'connect';

lives_ok {
	$mq->ChannelOpen(
		channel => 1,
	);
} 'channel.open';

sleep .5;

lives_ok { $mq->Heartbeat(); } 'heartbeat';

sleep .5;

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "testytest",
		payload => "Magic Transient Payload",
	);
} "basic.publish";

sleep(4);

throws_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "testytest",
		payload => "Magic Transient Payload",
	);
} qr/Connection reset by peer/, "failed publish";

1;
