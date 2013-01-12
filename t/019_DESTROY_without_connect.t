use strict;
use warnings;
no warnings 'uninitialized';
use Test::More tests => 3;

my $host = $ENV{MQHOST} || "dev.rabbitmq.com";

use_ok('Net::RabbitMQ');

# Make sure we don't crash on destroy, if we haven't connected.
eval {
	my $mq = Net::RabbitMQ->new();
	ok($mq);
};
is($@, '', "connect");

1;
