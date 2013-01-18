use Test::More tests => 13;
use Test::Exception;
use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok('Net::AMQP::RabbitMQ');

ok( my $mq = Net::AMQP::RabbitMQ->new() );

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

lives_ok {
	$mq->ExchangeDeclare(
		channel => 1,
		exchange => 'perl_test_headers',
		exchange_type => 'direct',
	);
} 'exchange.declare';

lives_ok {
	$mq->QueueDeclare(
		channel => 1,
		queue => "nr_test_hole",
		durable => 1,
		exclusive => 0,
		auto_delete => 0,
	);
} "queue_declare";

lives_ok {
	$mq->QueueBind(
		channel => 1,
		queue => "nr_test_hole",
		exchange => "perl_test_headers",
		routing_key => "nr_test_route",
	);
} "queue_bind";

lives_ok {
	1 while($mq->BasicGet( channel => 1, queue => "nr_test_hole" ));
} "drain queue";

my $headers = {
	abc => 123,
	def => 'xyx',
	head3 => 3,
	head4 => 4,
	head5 => 5,
	head6 => 6,
	head7 => 7,
	head8 => 8,
	head9 => 9,
	head10 => 10,
	head11 => 11,
	head12 => 12,
};
lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "nr_test_route",
		payload => "Header Test",
		exchange => "perl_test_headers",
		props => {
			headers => $headers,
		},
	);
} "publish" ;

lives_ok {
	$mq->BasicConsume(
		channel => 1,
		queue => "nr_test_hole",
		consumer_tag => 'ctag',
		no_ack => 1,
		exclusive => 0,
	);
} "consume";

my %msg;
lives_ok { %msg = $mq->Receive() } 'recv';

is( $msg{payload}, 'Header Test', "Received body" );

is_deeply(
	$msg{content_header_frame}{header_frame}{headers},
	$headers,
	"Received headers"
);

1;
