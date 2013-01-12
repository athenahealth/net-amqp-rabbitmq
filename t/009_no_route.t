use strict;
use warnings;
no warnings 'uninitialized';

use Test::More tests => 9;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ');

my $mq = Net::RabbitMQ->new();
ok($mq);

my $result = $mq->connect($host, {user => "guest", password => "guest"});
ok($result, 'connect');

eval { $mq->channel_open(1); };
is($@, '', 'channel_open');

eval { $mq->confirm_select( 1 ); };
is($@, '', 'confirm_select');

eval { $mq->publish(1, "nr_test_route", "Magic Payload"); };
is($@, '', 'good pub');

eval { $mq->confirm_delivery( 1 ); };
is($@, '', 'good pub confirmed');

eval { $mq->publish(1, "nr_test_route", "Magic Payload", { mandatory => 1, expiration => 0}); };
is($@, '', 'bad pub');

eval { $mq->confirm_delivery( 1 ); };
is($@, "delivery returned: NO_ROUTE\n", 'bad pub confirmed');

$mq->disconnect();

