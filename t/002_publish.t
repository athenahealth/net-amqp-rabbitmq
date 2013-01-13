use Test::More tests => 8;
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
	);
} 'connect';

lives_ok {
	$mq->ChannelOpen(
		channel => 1,
	);
} 'channel.open';

lives_ok {
	$mq->QueueDeclare(
		channel => 1,
		queue => "perl_test_queue",
		passive => 0,
		durable => 1,
		exclusive => 0,
		auto_delete => 0,
	);
} "queue.declare";

lives_ok {
	$mq->QueueBind(
		channel => 1,
		queue => "perl_test_queue",
		exchange => "nr_test_x",
		routing_key => "perl_test_queue",
	);
} "queue.bind";

lives_ok {
	1 while( $mq->BasicGet( channel => 1, queue => "nr_test_hole" ) );
} "drain queue";

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "nr_test_route",
		payload => "Magic Payload",
		exchange => "nr_test_x",
		content_type => 'text/plain',
		content_encoding => 'none',
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
} "basic.publish";

1;
