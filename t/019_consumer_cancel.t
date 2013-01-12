use strict;
use warnings;
no warnings 'uninitialized';
use Test::More tests => 9;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ');

my $mq = Net::RabbitMQ->new();
ok($mq);

eval { $mq->connect($host, { user => "guest", password => "guest" }) };
is($@, '', "connect");

eval { $mq->channel_open(1); };
is($@, '', "channel_open");

my $queuename = "nr_test_consumer_cancel";
eval { $mq->queue_declare(1, $queuename); };
is($@, '', "declare");

my $ctag = eval { $mq->consume(1, $queuename) };
is($@, '', "consume");

my $cancel;
$mq->basic_cancel(sub{
	my $channel = shift;
	$cancel = shift;
	die "Got our cancel\n";
});

eval { $mq->queue_delete(1, $queuename, { if_unused => 0 } ) };
is($@, "", 'deleted');

eval { $mq->recv() };
is($@, "Got our cancel\n", 'canceled');
is($cancel->{consumer_tag}, $ctag, "ctag");


1;
