use strict;
use warnings;
no warnings 'uninitialized';

use Test::More tests => 6;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ');

my $mq = Net::RabbitMQ->new();
ok($mq);

eval { $mq->connect($host, { user => "guest", password => "guest" }); };
is($@, '', "connect");
eval { $mq->channel_open(1); };
is($@, '', "channel_open");
eval { $mq->queue_declare(1, "nr_test_delete", { passive => 0, durable => 1, exclusive => 0, auto_delete => 0 }); };
is($@, '', "queue_declare");

eval { $mq->queue_delete(1, "nr_test_delete", { if_empty => 1, if_unused => 1 }); };
is($@, '', "queue_delete");

1;
