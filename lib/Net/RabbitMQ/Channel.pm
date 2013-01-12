package M::Channel;

use strict;
use warnings;

use Net::AMQP;

sub new {
	my ( $class, $args ) = @_;

	my $self = bless {
		BROKER => $args->{BROKER},
		CHANNEL => $args->{CHANNEL},
	}, $class;


	return $self;
}

sub Broker {
	my ( $self, $args ) = @_;

	return $self->{BROKER};
}

sub Channel {
	my ( $self, $args ) = @_;
	return $self->{CHANNEL};
}

sub Default {
	my ( $args, $arg, $default ) = @_;
	my $ret = $args->{$arg};
	if( ! defined $ret ) {
		$ret = $default;
	}
	return $ret;
}

sub Declare {
	my ( $self, $args ) = @_;

	my %opts = (
		queue     => Default( $args, 'queue', undef ),
		ticket    => Default( $args, 'ticket',    0 ),
		durable   => Default( $args, 'durable',   1 ),
		no_local  => Default( $args, 'no_local',  0 ),
		no_ack    => Default( $args, 'no_ack',    0 ),
		exclusive => Default( $args, 'exclusive', 0 ),
		passive   => Default( $args, 'passive',   0 ),
		nowait    => Default( $args, 'nowait',    0 ),
	);
	
	my $declareok = $self->Broker->RabbitRPC({
		CHANNEL => 2,
		OUTPUT => [
			Net::AMQP::Frame::Method->new(
				method_frame => Net::AMQP::Protocol::Queue::Declare->new(
					%opts
				),
			),
		],
		RESPONSETYPE => 'Net::AMQP::Protocol::Queue::DeclareOk',
	})->method_frame;

	return {
		QUEUE => $declareok->queue,
		CONSUMERS => $declareok->consumer_count,
		MESSAGES => $declareok->message_count,
	};
}

sub Cancel {
	my ( $self, $args ) = @_;
	my $consumertag = $args->{CONSUMERTAG};

	$self->Broker->RabbitRPC({
		CHANNEL => 2,
		OUTPUT => [
			Net::AMQP::Protocol::Basic::Cancel->new(
				consumer_tag => $consumertag,
			),
		],
		RESPONSETYPE => 'Net::AMQP::Protocol::Basic::CancelOk',
	});
}

sub Ack {
	my ( $self, $args ) = @_;
	my $frame = $args->{FRAME};
	d::D "Ack", $args->{FRAME};

	$self->Broker->RabbitRPC({
		CHANNEl => $self->Channel,
		OUTPUT => [
			Net::AMQP::Protocol::Basic::Ack->new(
				delivery_tag => $frame->method_frame->{delivery_tag}
			),
		],
		RESPONSETYPE => undef
	});
}


sub Reject {
	my ( $self, $args ) = @_;
	my $frame = $args->{FRAME};

	$self->Broker->RabbitRPC({
		CHANNEl => $self->Channel,
		OUTPUT => [
			Net::AMQP::Protocol::Basic::Reject->new(
				delivery_tag => $frame->delivery_tag
			),
		],
		RESPONSETYPE => undef
	});
}

sub Qos {
	my ( $self, $args ) = @_;

	my %opts = (
		prefect_size  => Default( $args, 'PREFETCHSIZE', 0 ),
		prefect_count => Default( $args, 'PREFETCHCOUNT', 1 ),
		global        => Default( $args, 'GLOBAL', 0 ),
	);

	$self->Broker->RabbitRPC({
		CHANNEL => $self->Channel,
		OUTPUT => [
			Net::AMQP::Protocol::Basic::Qos->new(
				%opts,
			),
		],
		RESPONSETYPE => 'Net::AMQP::Protocol::Basic::QosOk',
	});
}

# Return consumer tag of queue.
sub Consume {
	my ( $self, $args ) = @_;

	my %opts = (
		queue     => Default( $args, 'queue', undef ),
		ticket    => Default( $args, 'ticket',    0 ),
		durable   => Default( $args, 'durable',   1 ),
		no_local  => Default( $args, 'no_local',  0 ),
		no_ack    => Default( $args, 'no_ack',    0 ),
		exclusive => Default( $args, 'exclusive', 0 ),
		nowait    => Default( $args, 'nowait',    0 ),
	);

	return $self->Broker->RabbitRPC({
		CHANNEL => 2,
		OUTPUT => [
			Net::AMQP::Frame::Method->new(
				method_frame => Net::AMQP::Protocol::Basic::Consume->new(
					%opts
				),
			),
		],
		RESPONSETYPE => 'Net::AMQP::Protocol::Basic::ConsumeOk'
	})->method_frame->consumer_tag;
}

sub Publish {
	my($self, $args ) = @_;
	my $queue = $args->{QUEUE};
	my $message = $args->{MESSAGE};

	my %methodopts = (
		ticket => 0,
		#exchange => '', # default exchange
		routing_key => $queue, # route to my queue
		mandatory => 1,
		#immediate => 0,
	);

	my %contentopts = (
		content_type => 'application/octet-stream',
		#content_encoding => '',
		#headers => {},
		delivery_mode => 1, # non-persistent
		priority => 1,
		#correlation_id => '',
		#reply_to => '',
		#expiration => '',
		#message_id => '',
		#timestamp => time,
		#type => '',
		#user_id => '',
		#app_id => '',
		#cluster_id => '',
	);

	$self->Broker->_Send({
		CHANNEL => 2,
		OUTPUT => Net::AMQP::Protocol::Basic::Publish->new(
			%methodopts,
		),
		NOCHECK => 1,
	});

	$self->Broker->_Send({
		CHANNEL => 2,
		OUTPUT => Net::AMQP::Frame::Header->new(
			weight => 0,
			body_size => length($message),
			header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
				%contentopts
			),
		),
		NOCHECK => 1,
	});
	$self->Broker->_Send({
		CHANNEL => 2,
		OUTPUT => Net::AMQP::Frame::Body->new(
			payload => $message,
		),
	});
}



1;
