use Test::More tests => 5;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok( 'Net::AMQP::RabbitMQ::PP' );

ok( my $mq = Net::AMQP::RabbitMQ::PP->new() );

lives_ok {
	$mq->connect(
		host => $host,
		username => "guest",
		password => "guest"
	);
} 'connecting';

lives_ok {
	$mq->channel_open( channel => 1 );
} 'channel.open';

lives_ok {
	$mq->exchange_declare(
		channel => 1,
		exchange => "perl_exchange",
		exchange_type => "direct",
		passive => 0,
		durable => 1,
		auto_delete => 0,
	);
} 'exchange.declare';

1;
