use Test::More tests => 5;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{'MQHOST'} || "dev.rabbitmq.com";

use_ok( 'Net::AMQP::RabbitMQ' );

ok( my $mq = Net::AMQP::RabbitMQ->new() );

lives_ok {
	$mq->Connect(
		host => $host,
		username => "guest",
		password => "guest"
	);
} 'connecting';

lives_ok {
	$mq->ChannelOpen( channel => 1 );
} 'channel.open';

lives_ok {
	$mq->ExchangeDeclare(
		channel => 1,
		exchange => "perl_exchange",
		exchange_type => "direct",
		passive => 0,
		durable => 1,
		auto_delete => 0,
	);
} 'exchange.declare';

1;
