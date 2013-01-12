use strict;
use warnings;
no warnings 'uninitialized';

use Test::More tests => 7;
use Data::Dumper;
use Time::HiRes;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";
use_ok('Net::RabbitMQ');

my $mq = Net::RabbitMQ->new();
ok($mq);

eval { $mq->connect($host, { user => "guest", password => "guest", heartbeat => 1 }); };
is($@, '', "connect");

eval { $mq->channel_open(1); };
is($@, '', "channel_open");
sleep .5;
eval { $mq->heartbeat(); };
is($@, '', "heartbeat");
sleep .5;
eval { $mq->publish(1, "nr_test_q", "Magic Transient Payload", { exchange => "nr_test_x", immediate => 1, mandatory => 1 }); };
is($@, '', "working publish");

diag "Sleeping for 4 seconds";
sleep(4);
eval { $mq->publish(1, "nr_test_q", "Magic Transient Payload", { exchange => "nr_test_x", immediate => 1, mandatory => 1 }); };
is($@, "publish: Connection reset by peer\n", "failed publish");

1;
