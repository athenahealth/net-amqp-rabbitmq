# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 2;

use_ok( 'Net::AMQP::RabbitMQ::PP' );

isa_ok( my $object = Net::AMQP::RabbitMQ::PP->new (), 'Net::AMQP::RabbitMQ::PP');


