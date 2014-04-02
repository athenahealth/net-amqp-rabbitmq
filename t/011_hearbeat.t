use Test::More tests => 7;
use Test::Exception;
use English qw( -no_match_vars );
use strict;
use warnings;

use Time::HiRes;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";
use_ok('Net::AMQP::RabbitMQ::PP');

ok( my $mq = Net::AMQP::RabbitMQ::PP->new() );

lives_ok {
	$mq->connect(
		host => $host,
		username => "guest",
		password => "guest",
		heartbeat => 1,
	);
} 'connect';

lives_ok {
	$mq->channel_open(
		channel => 1,
	);
} 'channel.open';

sleep .5;

lives_ok { $mq->heartbeat(); } 'heartbeat';

sleep .5;

lives_ok {
	$mq->basic_publish(
		channel => 1,
		routing_key => "testytest",
		payload => "Magic Transient Payload",
	);
} "basic.publish";

sleep(4);

my $exception;
if( $OSNAME =~ /MSWin32/ ) {
	$exception = qr/An existing connection was forcibly closed/;
}
else {
	$exception = qr/Connection reset by peer/;
}

throws_ok {
	$mq->basic_publish(
		channel => 1,
		routing_key => "testytest",
		payload => "Magic Transient Payload",
	);
} $exception, "failed publish";

1;
