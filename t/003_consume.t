use Test::More tests => 9;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok( 'Net::RabbitMQ::Perl' );

ok( my $mq = Net::RabbitMQ::Perl->new() );

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

my $testqueue;
lives_ok {
	$testqueue = $mq->QueueDeclare(
		channel => 1,
		passive => 0,
		durable => 0,
		exclusive => 0,
		auto_delete => 1,
	)->queue;
} 'queue.declare';

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => $testqueue,
		payload => "awesome!",
		props => {
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
		},
	);
} 'basic.publish';

my $consumertag;
lives_ok {
	$consumertag = $mq->BasicConsume(
		channel => 1,
		queue => $testqueue,
		consumer_tag => 'ctag',
		no_local => 0,
		no_ack => 1,
		exclusive => 0,
	)->consumer_tag;
} "consume";

my %rv;
lives_ok {
	local $SIG{ALRM} = sub {
		die "Timeout";
	};
	alarm 5;
	%rv = $mq->Receive();
	alarm 0;
} "recv";

is_deeply(
	{ %rv },
	{
		payload => 'awesome!',
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => 8,
			type_id => 2,
			weight => 0,
			payload => '',
			class_id => 60,
			channel => 1,
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
				priority => 2,
				message_id => 'ABC',
				content_type => 'text/plain',
				content_encoding => 'none',
				correlation_id => '123',
				reply_to => 'somequeue',
				expiration => 60000,
				type => 'notmytype',
				user_id => 'guest',
				app_id => 'idd',
				delivery_mode => 1,
				timestamp => 1271857990,
			),
		),
		delivery_frame => Net::AMQP::Frame::Method->new(
			type_id => 1,
			payload => '',
			channel => 1,
			method_frame => Net::AMQP::Protocol::Basic::Deliver->new(
				redelivered => 0,
				delivery_tag => 1,
				routing_key => $testqueue,
				exchange => '',
				consumer_tag => $consumertag,
			),
		),
	},
	"payload"
);

1;
