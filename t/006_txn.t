use Test::More tests => 14;
use Test::Exception;

use strict;
use warnings;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ::Perl');

ok( my $mq = Net::RabbitMQ::Perl->new() );

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

my $queuename = '';
lives_ok {
	$queuename = $mq->QueueDeclare(
		channel => 1,
		auto_delete => 1,
	)->queue;
} "queue.declare";

isnt($queuename, '');

my $exchangename = 'perl_transaction_exchange';
lives_ok {
	$mq->ExchangeDelete(
		channel => 1,
		exchange => $exchangename,
	);

	$mq->ExchangeDeclare(
		channel => 1,
		exchange => $exchangename,
		exchange_type => 'direct',
		auto_delete => 1,
	);
} "exchange.declare";

lives_ok {
	$mq->QueueBind(
		channel => 1,
		queue => $queuename,
		exchange => $exchangename,
		routing_key => "transaction test key",
	);
} "queue.bind";

lives_ok {
	$mq->TxSelect(
		channel => 1,
	);
} "tx.select";

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "transaction test key",
		payload => "to be rollbacked",
		exchange => $exchangename,
	);
} "basic.publish";

lives_ok {
	$mq->TxRollback(
		channel => 1,
	);
} 'tx.rollback';

lives_ok {
	$mq->BasicPublish(
		channel => 1,
		routing_key => "transaction test key",
		payload => "to be committed",
		exchange => $exchangename,
	);
} 'basic.publish';

lives_ok {
	$mq->TxCommit(
		channel => 1,
	);
} 'tx.commit';

is_deeply(
	{
		$mq->BasicGet(
			channel => 1,
			queue => $queuename,
		),
	},
	{
		content_header_frame => Net::AMQP::Frame::Header->new(
			body_size => 15,
			type_id => 2,
			weight => 0,
			payload => '',
			class_id => '60',
			channel => 1,
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
			),
		),
		payload => 'to be committed',
	},
	'commited payload'
);

1;
