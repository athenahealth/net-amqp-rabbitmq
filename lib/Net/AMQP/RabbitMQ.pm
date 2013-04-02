package Net::AMQP::RabbitMQ;

use strict;
use warnings;

our $VERSION = '0.01';

use Carp;
use Cwd;
use English qw(-no_match_vars);
use File::ShareDir;
use IO::Select;
use IO::Socket::INET;
use List::MoreUtils;
use Net::AMQP;
use Sys::Hostname;
use Try::Tiny;
use Time::HiRes;

sub new {
	my ( $class, %parameters ) = @_;

	if( ! %Net::AMQP::Protocol::spec ) {
		Net::AMQP::Protocol->load_xml_spec(
			File::ShareDir::dist_file(
				'Net-AMQP-RabbitMQ',
				'amqp0-9-1.extended.xml'
			)
		);
	}

	my $self = bless {}, ref $class || $class;

	return $self;
}

sub connect {
	my ( $self, %args ) = @_;

	try {
		local $SIG{ALRM} = sub {
			Carp::croak 'Timed out';
		};

		if( $args{timeout} ) {
			Time::HiRes::alarm( $args{timeout} );
		}

		$self->_set_handle(
			IO::Socket::INET->new(
				PeerAddr => $args{host} || 'localhost',
				PeerPort => $args{port} || 5672,
				Proto => 'tcp',
			) or Carp::croak "Could not connect: $EVAL_ERROR"
		);

		$self->_select( IO::Select->new( $self->_get_handle ) );

		if( $args{timeout} ) {
			Time::HiRes::alarm( 0 );
		}
	}
	catch {
		Carp::croak $_;
	};

	$self->_get_handle->autoflush( 1 );

	my $password = $args{password} || 'guest';
	my $username = $args{username} || 'guest';
	my $virtualhost = $args{virtual_host} || '/';
	my $heartbeat = $args{heartbeat} || 0;


	# Backlog of messages.
	$self->_backlog( [] );

	$self->_startup(
		username => $username,
		password => $password,
		virtual_host => $virtualhost,
		heartbeat => $heartbeat,
	);

	return $self;
}

sub set_keepalive {
	my ( $self, %args ) = @_;
	my $handle = $self->_get_handle;
	my $idle = $args{idle};
	my $count = $args{count};
	my $interval = $args{interval};

	if( eval { require Socket::Linux } ) {
		# Turn on keep alive probes.
		defined $handle->sockopt( SO_KEEPALIVE, 1 )
			or Carp::croak "Could not turn on tcp keep alive: $OS_ERROR";

		# Time between last meaningful packet and first keep alive
		if( defined $idle ) {
			defined $handle->setsockopt( Socket::IPPROTO_TCP, Socket::Linux::TCP_KEEPIDLE(), $idle )
				or Carp::croak "Could not set keep alive idle time: $OS_ERROR";
		}

		# Time between keep alives
		if( defined $interval ) {
			defined $handle->setsockopt( Socket::IPPROTO_TCP, Socket::Linux::TCP_KEEPINTVL(), $interval )
				or Carp::croak "Could not set keep alive interval time: $OS_ERROR";
		}

		# Number of failures to allow
		if( defined $count ) {
			defined $handle->setsockopt( Socket::IPPROTO_TCP, Socket::Linux::TCP_KEEPCNT(), $count )
				or Carp::croak "Could not set keep alive count: $OS_ERROR";
		}
	}
	else {
		Carp::croak "Unable to find constants for keepalive settings";
	}

	return;
}

sub _default {
	my ( $self, $key, $value, $default ) = @_;
	if( defined $value ) {
		return ( $key => $value );
	}
	elsif( defined $default ) {
		return $key => $default;
	}
	return;
}

sub _startup {
	my ( $self, %args ) = @_;

	my $password = $args{password};
	my $username = $args{username};
	my $virtualhost = $args{virtual_host};

	# Startup is two-way rpc. The server starts by asking us some questions, we
	# respond then tell it we're ready to consume everything.
	#
	# The initial hand shake is all on channel 0.

	# Kind of non obvious but we're waiting for a response from the server to
	# our initial headers.
	$self->rpc_request(
		channel => 0,
		output => [ Net::AMQP::Protocol->header ],
		response_type => 'Net::AMQP::Protocol::Connection::Start',
	);

	my %client_properties = (
		# Can plug all sorts of random stuff in here.
		platform => 'Perl/NetAMQP',
		product => Cwd::abs_path( $PROGRAM_NAME ),
		information => 'http://github.com/emarcotte/net-amqp-rabbitmq',
		version => $VERSION,
		host => hostname(),
	);

	if( Net::AMQP::Common->can("true") ) {
		$client_properties{capabilities}{consumer_cancel_notify} = Net::AMQP::Common->true;
	}

	my $servertuning = $self->rpc_request(
		channel => 0,
		output => [
			Net::AMQP::Protocol::Connection::StartOk->new(
				client_properties => \%client_properties,
				mechanism => 'AMQPLAIN',
				response => {
					LOGIN => $username,
					PASSWORD => $password,
				},
				locale => 'en_US',
			),
		],
		response_type => 'Net::AMQP::Protocol::Connection::Tune',
	);

	my $serverheartbeat = $servertuning->heartbeat;
	my $heartbeat = $args{heartbeat} || 0;

	if( $serverheartbeat != 0 && $serverheartbeat < $heartbeat ) {
		$heartbeat = $serverheartbeat;
	}

	# Respond to the tune request with tuneok and then officially kick off a
	# connection to the virtual host.
	$self->rpc_request(
		channel => 0,
		output => [
			Net::AMQP::Protocol::Connection::TuneOk->new(
				channel_max => 0,
				frame_max => 131072,
				heartbeat => $heartbeat,
			),
			Net::AMQP::Protocol::Connection::Open->new(
				virtual_host => $virtualhost,
			),
		],
		response_type => 'Net::AMQP::Protocol::Connection::OpenOk',
	);

	return;
}

sub rpc_request {
	my ( $self, %args ) = @_;
	my $channel = $args{channel};
	my @output = @{ $args{output} || [] };

	my @responsetype ;
	if( $args{response_type} ) {
		@responsetype = ref $args{response_type}
			? @{ $args{response_type} }
			: ( $args{response_type} );
	}

	foreach my $output ( @output ) {
		$self->_send(
			channel => $channel,
			output => $output,
		);
	}

	if( ! @responsetype ) {
		return;
	}

	return $self->_local_receive(
		channel => $channel,
		method_frame => [ @responsetype ],
	)->method_frame;
}

sub _backlog {
	my ( $self, $backlog ) = @_;
	$self->{backlog} = $backlog if $backlog;
	return $self->{backlog};
}

sub _select {
	my ( $self, $select ) = @_;
	$self->{select} = $select if $select;
	return $self->{select};
}

sub _clear_handle {
	my ( $self ) = @_;
	$self->_set_handle( undef );
	return;
}

sub _set_handle {
	my ( $self, $handle ) = @_;
	$self->{handle} = $handle;
	return;
}

sub _get_handle {
	my ( $self ) = @_;
	my $handle = $self->{handle};
	if( ! $handle ) {
		Carp::croak "Not connected to broker.";
	}
	return $handle;
}

sub _read_length {
	my ( $self, $data, $length ) = @_;
	my $bytesread = $self->_get_handle->sysread( $$data, $length );
	if( ! defined $bytesread ) {
		Carp::croak "Read error: $OS_ERROR";
	}
	elsif( $bytesread == 0 ) {
		$self->_clear_handle;
		Carp::croak "Connection closed";
	}
	return $bytesread;
}

sub _read {
	my ( $self, %args ) = @_;
	my $data;
	my $stack;

	my $timeout = $args{timeout};
	if( ! $timeout || $self->_select->can_read( $timeout ) ) {
		# read length (in bytes) of incoming frame, by reading first 8 bytes and
		# unpacking.
		my $bytesread = $self->_read_length( \$data, 8 );

		$stack .= $data;
		my ( $type_id, $channel, $length ) = unpack 'CnN', substr $data, 0, 7, '';
		$length ||= 0;

		# read until $length bytes read
		while ( $length > 0 ) {
			$bytesread = $self->_read_length( \$data, $length );
			$length -= $bytesread;
			$stack .= $data;
		}

		return Net::AMQP->parse_raw_frames( \$stack );
	}
	return ();
}

sub _check_frame {
	my( $self, $frame, %args ) = @_;

	if( defined $args{channel} && $frame->channel != $args{channel} ) {
		return 0;
	}

	if( defined $args{type} && $args{type} ne ref $frame ) {
		return 0;
	}

	if( defined $args{method_frame} &&
		! List::MoreUtils::any { ref $frame->{method_frame} eq $_ } @{ $args{method_frame} } ) {
		return 0;
	}

	if( defined $args{header_frame} &&
		! List::MoreUtils::any { ref $frame->{header_frame} eq $_ } @{ $args{header_frame} } ) {
		return 0
	}

	return 1;
}

sub _first_in_frame_list {
	my( $self, $list, %args ) = @_;
	my $firstindex = List::MoreUtils::firstidx { $self->_check_frame( $_, %args) } @{ $list };
	my $frame;
	if( $firstindex >= 0 ) {
		$frame = $list->[$firstindex];
		splice @{ $list }, $firstindex, 1;
	}
	return $frame;
}

sub _receive_cancel {
	my( $self, %args ) = @_;

	my $cancel_frame = $args{cancel_frame};

	if( my $sub = $self->basic_cancel_callback ) {
		$sub->(
			cancel_frame => $cancel_frame,
		);
	};

	return;
}

sub _local_receive {
	my( $self, %args ) = @_;

	# Check the backlog first.
	if( my $frame = $self->_first_in_frame_list( $self->_backlog, %args ) ) {
		return $frame;
	}

	my $due_by = Time::HiRes::time() + ($args{timeout} || 0);

	while( 1 ) {
		my $timeout = $args{timeout} ? $due_by - Time::HiRes::time() : 0;
		if( $args{timeout} && $timeout <= 0 ) {
			return;
		}

		my @frames = $self->_read(
			timeout => $timeout,
		);

		foreach my $frame ( @frames ) {
			# TODO March of the ugly.
			# TODO Reasonable cancel handlers look like ?
			if( $self->_check_frame( $frame, ( method_frame => [ 'Net::AMQP::Protocol::Basic::Cancel' ] ) ) ) {
				$self->_receive_cancel(
					cancel_frame => $frame,
				);
			}

			# TODO This is ugly as sin.
			# Messages on channel 0 saying that the connection is closed. That's
			# a big error, we should probably mark this session as invalid.
			# TODO could comebind checks, mini optimization
			if( $self->_check_frame( $frame, ( method_frame => [ 'Net::AMQP::Protocol::Connection::Close'] ) ) ) {
				$self->_clear_handle;
				Carp::croak sprintf 'Connection closed %s', $frame->method_frame->reply_text;
			}
			# TODO only filter for the channel we passed?
			elsif( $self->_check_frame( $frame, ( method_frame => [ 'Net::AMQP::Protocol::Channel::Close'] ) ) ) {
				# TODO Mark the channel as dead?
				Carp::croak sprintf 'Channel %d closed %s', $frame->channel, $frame->method_frame->reply_text;
			}
		}

		my $frame = $self->_first_in_frame_list( \@frames, %args );
		push @{ $self->_backlog }, @frames;
		return $frame if $frame;
	}

	return;
}

sub _receive_delivery {
	my ( $self, %args ) = @_;

	my $headerframe = $self->_local_receive(
		channel => $args{channel},
		header_frame => [ 'Net::AMQP::Protocol::Basic::ContentHeader' ],
	);

	my $length = $headerframe->{body_size};
	my $payload = '';

	while( length( $payload ) < $length ) {
		my $frame = $self->_local_receive(
			channel => $args{channel},
			type => 'Net::AMQP::Frame::Body',
		);
		$payload .= $frame->{payload};
	}

	return (
		content_header_frame => $headerframe,
		payload => $payload,
	);
}

sub receive {
	my ( $self, %args ) = @_;

	my $nextframe = $self->_local_receive(
		timeout => $args{timeout},
		channel => $args{channel},
	);

	if( ref $nextframe eq 'Net::AMQP::Frame::Method' ) {
		my $method_frame = $nextframe->method_frame;

		if( ref $method_frame eq 'Net::AMQP::Protocol::Basic::Deliver' ) {
			return {
				$self->_receive_delivery(
					channel => $nextframe->channel,
				),
				delivery_frame => $nextframe,
			};
		}
	}

	return $nextframe;
}

sub disconnect {
	my($self, $args ) = @_;

	$self->rpc_request(
		channel => 0,
		output => [
			Net::AMQP::Protocol::Connection::Close->new(
			),
		],
		resposnse_type => 'Net::AMQP::Protocol::Connection::CloseOk',
	);

	if( ! $self->_get_handle->close() ) {
		$self->_clear_handle;
		Carp::croak "Could not close socket: $OS_ERROR";
	}

	return;
}

sub _send {
	my ( $self, %args ) = @_;
	my $channel = $args{channel};
	my $output = $args{output};

	my $write;
	if( ref $output ) {
		if ( $output->isa('Net::AMQP::Protocol::Base') ) {
			$output = $output->frame_wrap;
		}

		if( ! defined $output->channel ) {
			$output->channel( $channel )
		}

		$write = $output->to_raw_frame();
	}
	else {
		$write = $output;
	}

	$self->_get_handle->syswrite( $write ) or
		Carp::croak "Could not write to socket: $OS_ERROR";

	return;
}

sub channel_open {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Channel::Open->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Channel::OpenOk',
	);
}

sub exchange_declare {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Exchange::Declare->new(
				exchange => $args{exchange},
				type => $args{exchange_type},
				passive => $args{passive},
				durable => $args{durable},
				auto_delete => $args{auto_delete},
			),
		],
		response_type => 'Net::AMQP::Protocol::Exchange::DeclareOk',
	);
}

sub exchange_delete {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Exchange::Delete->new(
				exchange => $args{exchange},
				if_unused => $args{if_unused},
			),
		],
		response_type => 'Net::AMQP::Protocol::Exchange::DeleteOk',
	);
}

sub queue_declare {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return$self->rpc_request(
		channel => $channel,
		output => [
			 Net::AMQP::Protocol::Queue::Declare->new(
				queue => $args{queue},
				passive => $args{passive},
				durable => $args{durable},
				exclusive => $args{exclusive},
				auto_delete => $args{auto_delete},
				arguments => {
					$self->_default( 'x-expires', $args{expires} ),
				},
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::DeclareOk',
	);
}

sub queue_bind {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};
	my %flags = (
		queue => $args{queue},
		exchange => $args{exchange},
		routing_key => $args{routing_key},
		$self->_default( 'arguments', $args{headers} ),
	);

	return $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Queue::Bind->new(
				queue => $args{queue},
				exchange => $args{exchange},
				routing_key => $args{routing_key},
				$self->_default( 'arguments', $args{headers} ),
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::BindOk',
	);
}

sub queue_delete {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Queue::Delete->new(
				queue => $args{queue},
				if_empty => $args{if_empty},
				if_unused => $args{if_unused},
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::DeleteOk',
	);
}

sub queue_unbind {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	my %flags = (
		queue => $args{queue},
		exchange => $args{exchange},
		routing_key => $args{routing_key},
	);

	if( $args{headers} ) {
		$flags{arguments} = $args{headers};
	}

	return $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Queue::Unbind->new( %flags ),
		],
		response_type => 'Net::AMQP::Protocol::Queue::UnbindOk',
	);
}

sub queue_purge {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Queue::Purge->new(
				queue => $args{queue},
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::PurgeOk',
	);
}

sub basic_ack {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Basic::Ack->new(
				delivery_tag => $args{delivery_tag},
				multiple => $args{multiple},
			),
		],
	);
}

sub basic_cancel_callback {
	my ( $self, %args ) = @_;
	$self->{basic_cancel_callback} = $args{callback} if( $args{callback} );
	return $self->{basic_cancel_callback};
};

sub basic_cancel {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Basic::Cancel->new(
				queue => $args{queue},
				consumer_tag => $args{consumer_tag},
			),
		],
		response_type => 'Net::AMQP::Protocol::Basic::CancelOk',
	);
}

sub basic_get {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	my $get = $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Basic::Get->new(
				queue => $args{queue},
				no_ack => $args{no_ack},
			),
		],
		response_type => [qw(
			Net::AMQP::Protocol::Basic::GetEmpty
			Net::AMQP::Protocol::Basic::GetOk
		)],
	);

	if( ref $get eq 'Net::AMQP::Protocol::Basic::GetEmpty' ) {
		return;
	}
	else {
		return {
			$self->_receive_delivery(
				channel => $channel,
			),
		}
	}
}

sub basic_publish {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};
	my $payload = $args{payload};

	return $self->rpc_request(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Basic::Publish->new(
				exchange => $args{exchange},
				routing_key => $args{routing_key},
				mandatory => $args{mandatory},
				immediate => $args{immediate},
			),
			Net::AMQP::Frame::Header->new(
				body_size => length( $payload ),
				channel => $channel,
				header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
					map { $args{props}{$_} ? ( $_ => $args{props}{$_} ) : () } qw(
						content_type
						content_encoding
						headers
						delivery_mode
						priority
						correlation_id
						reply_to
						expiration
						message_id
						timestamp
						type
						user_id
						app_id
						cluster_id
					),
				),
			),
			Net::AMQP::Frame::Body->new(
				payload => $payload,
			),
		],
	);
}

sub basic_consume {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Basic::Consume->new(
				queue => $args{queue},
				exchange => $args{exchange},
				routing_key => $args{routing_key},
			),
		],
		response_type => 'Net::AMQP::Protocol::Basic::ConsumeOk',
	);
}

sub basic_reject {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Basic::Reject->new(
				delivery_tag => $args{delivery_tag},
			),
		],
	);
}

sub basic_qos {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Basic::Qos->new(
				global => $args{global},
				prefetch_count => $args{prefetch_count},
				prefect_size => $args{prefetch_size},
			),
		],
		response_type => 'Net::AMQP::Protocol::Basic::QosOk',
	);
}

sub transaction_select {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Tx::Select->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Tx::SelectOk',
	);
}

sub transaction_commit {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Tx::Commit->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Tx::CommitOk',
	);
}

sub transaction_rollback {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Tx::Rollback->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Tx::RollbackOk',
	);
}

sub confirm_select {
	my ( $self, %args ) = @_;

	return $self->rpc_request(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Confirm::Select->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Confirm::SelectOk',
	);
}

sub heartbeat {
	my ( $self, %args ) = @_;
	return $self->_send(
		channel => 0,
		output => Net::AMQP::Frame::Heartbeat->new(
		),
	);
}

1;

__END__

=head1 NAME

Net::AMQP::RabbitMQ - Perl-based RabbitMQ AMQP client

=head1 SYNOPSIS

    use Net::AMQP::RabbitMQ;

    my $connection = Net::AMQP::RabbitMQ->new();
    $connection->connect;
    $connection->basic_publish(
        payload => "Foo",
        routing_key => "foo.bar",
    );
    $connection->disconnect

=head1 DESCRIPTION

Stub documentation for this module was created by ExtUtils::ModuleMaker.
It looks like the author of the extension was negligent enough
to leave the stub unedited.

Blah blah blah.

=head1 VERSION

This is 0.1

=head1 SUBROUTINES/METHODS

=head2 new

Loads the AMQP protocol definition, primarily. Will not be an active
connection until Connect is called.

=head2 connect


$args{timeout}
$args{host}
$args{port}
$args{password}
$args{username}
$args{virtual_host}
$args{heartbeat}

=head2 _startup

Does the initial connection back-and-forth with Rabbit to configure the
connection before we start delivering messages.

=head1 BUGS AND LIMITATIONS

Please report all bugs to the issue tracker on github.
https://github.com/emarcotte/net-amqp-rabbitmq/issues

One known limitation is that we cannot automatically sending heartbeat frames in
a useful way.

=head1 SUPPORT

Use the issue tracker on github to reach out for support.
https://github.com/emarcotte/net-amqp-rabbitmq/issues

=head1 AUTHOR

	Eugene Marcotte
	athenahealth
	emarcotte@athenahealth.com
	http://athenahealth.com

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Eugene Marcotte

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=head1 INCOMPATIBILITIES

=head1 SEE ALSO

perl(1), Net::RabbitMQ, Net::AMQP

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES


=cut
