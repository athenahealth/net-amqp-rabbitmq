package M::Broker;

use strict;
use warnings;

use M::Channel;

use Net::AMQP;
use IO::Socket::INET;
use IO::Select;
use Sys::Hostname;
use Cwd;

use Carp qw(croak);
$Carp::Verbose = 1;
1;
