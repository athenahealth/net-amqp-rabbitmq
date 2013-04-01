use Test::More tests => 6;
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
} 'connect';

lives_ok {
	$mq->channel_open(
		channel => 1,
	);
};

# Second call to channel open is invalid.
throws_ok {
	$mq->channel_open(
		channel => 1,
	);
} qr/COMMAND_INVALID - second 'channel[.]open'/, 'channel.open dupe';

# The connection should now be invalid.
throws_ok {
	$mq->channel_open(
		channel => 1,
	);
} qr/Not connected to broker/, 'Not connected to broker';

1;
