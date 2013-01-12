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

my $ctag = eval { $mq->consume(1, "nr_test_hole", {consumer_tag=>'ctag', no_local=>0,no_ack=>1,exclusive=>0}); };
is($@, '', "consume");

eval { $mq->cancel(1, $ctag); };
is($@, '', "recv");

1;
