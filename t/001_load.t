# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 2;

use_ok( 'Net::RabbitMQ::Perl' );

isa_ok( my $object = Net::RabbitMQ::Perl->new (), 'Net::RabbitMQ::Perl');


