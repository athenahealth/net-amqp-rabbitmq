package Net::AMQP::RabbitMQ;

use strict;
use warnings;

use vars qw( $VERSION );
$VERSION = '0.01';

use Carp;
use Cwd;
use English qw(-no_match_vars);
use File::ShareDir;
use IO::Select;
use IO::Socket::INET;
use Net::AMQP;
use Sys::Hostname;
use List::MoreUtils;

=head1 SUBROUTINES

=head2 new

Loads the AMQP protocol definition, primarily. Will not be an active
connection until Connect is called.

=cut

sub new {
	my ( $class, %parameters ) = @_;

	Net::AMQP::Protocol->load_xml_spec(
		File::ShareDir::dist_file(
			'Net-RabbitMQ-Perl',
			'amqp0-9-1.extended.xml'
		)
	);

	my $self = bless( {}, ref( $class ) || $class );

	return $self;
}

sub Connect {
	my ( $self, %args ) = @_;

	my $host = $args{host} || 'localhost';
	my $password = $args{password} || 'guest';
	my $username = $args{username} || 'guest';
	my $port = $args{port} || 5672;
	my $virtualhost = $args{virtual_host} || '/';

	$self->{remote} = IO::Socket::INET->new(
		Proto => "tcp",
		PeerAddr => $host,
		PeerPort => $port,
	);

	if( ! $self->{remote} ) {
		Carp::croak "Could not connect $OS_ERROR";
	}

	$self->{select} = IO::Select->new( $self->{remote} );

	# Backlog of messages.
	$self->{backlog} = [];

	$self->_Startup(
		username => $username,
		password => $password,
		virtual_host => $virtualhost,
	);

	return $self;
}

=head2 _Startup

Does the initial connection back-and-forth with Rabbit to configure the
connection before we start delivering messages.

=cut

sub _Startup {
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
	$self->RabbitRPC(
		channel => 0,
		output => [ Net::AMQP::Protocol->header ],
		response_type => 'Net::AMQP::Protocol::Connection::Start',
	);

	$self->RabbitRPC(
		channel => 0,
		output => [
			Net::AMQP::Protocol::Connection::StartOk->new(
				client_properties => {
					# Can plug all sorts of random stuff in here.
					platform => 'Perl/NetAMQP/Athena',
					product => Cwd::abs_path( $0 ),
					information => 'http://athenahealth.com/',
					version => '1.0',
					host => hostname(),
				},
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

	# Respond to the tune request with tuneok and then officially kick off a
	# connection to the virtual host.
	$self->RabbitRPC(
		channel => 0,
		output => [
			Net::AMQP::Protocol::Connection::TuneOk->new(
				channel_max => 0,
				frame_max => 131072,
				heartbeat => 0,
			),
			Net::AMQP::Protocol::Connection::Open->new(
				virtual_host => $virtualhost,
			),
		],
		response_type => 'Net::AMQP::Protocol::Connection::OpenOk',
	);

	return;
}

sub RabbitRPC {
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
		$self->_Send(
			channel => $channel,
			output => $output,
		);
	}

	if( ! @responsetype ) {
		return;
	}

	return $self->_LocalReceive(
		channel => $channel,
		method_frame => [ @responsetype ],
	)->method_frame;
}

sub _Remote {
	my ( $self, %args ) = @_;
	return $self->{remote};
}

sub _Read {
	my ( $self, %args ) = @_;
	my $data;
	my $stack;
	my $timeout = $args{timeout};

	if( ! $timeout || $self->{select}->can_read( $timeout ) ) {

		# read length (in Bytes)
		my $bytesread = $self->_Remote->read( $data, 8 );
		if( !defined $bytesread ) {
			die "Connection closed";
		}

		$stack .= $data;
		my ( $type_id, $channel, $length ) = unpack( 'CnN', substr( $data, 0, 7, '' ) );
		$length ||= 0;

		# read until $length bytes read
		while ( $length > 0 ) {
			$bytesread = $self->_Remote->read( $data, $length );
			if( !defined $bytesread ) {
				die "Connection closed";
			}
			$length -= $bytesread;
			$stack .= $data;
		}

		return Net::AMQP->parse_raw_frames( \$stack );
	}
	return ();
}

sub _CheckFrame {
	my( $frame, %args ) = @_;

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

sub _FirstInFrameList {
	my( $list, %args ) = @_;
	my $firstindex = List::MoreUtils::firstidx { _CheckFrame( $_, %args ) } @$list;
	if( $firstindex < 0 ) {
		return;
	}
	my $frame = $list->[$firstindex];
	splice( @$list, $firstindex, 1 );
	return $frame;
}

sub _LocalReceive {
	my( $self, %args ) = @_;

	# Check the backlog first.
	if( my $frame = _FirstInFrameList( $self->{backlog}, %args ) ) {
		return $frame;
	}

	while( 1 ) {
		my @frames = $self->_Read();
		foreach my $frame ( @frames ) {
			# TODO This is ugly as sin.
			# Messages on channel 0 saying that the connection is closed. That's
			# a big error, we should probably mark this session as invalid.
			# TODO could comebind checks, mini optimization
			if( _CheckFrame( $frame, ( method_frame => [ 'Net::AMQP::Protocol::Connection::Close'] ) ) ) {
				Carp::croak sprintf(
					"Connection closed %s",
					$frame->method_frame->reply_text
				);
			}
			# TODO only filter for the channel we passed?
			elsif( _CheckFrame( $frame, ( method_frame => [ 'Net::AMQP::Protocol::Channel::Close'] ) ) ) {
				# TODO Mark the channel as dead?
				Carp::croak sprintf(
					"Channel %d closed %s",
					$frame->channel,
					$frame->method_frame->reply_text
				);
			}
		}

		my $frame = _FirstInFrameList( \@frames, %args );
		push( @{ $self->{backlog} }, @frames );
		return $frame if $frame;
	}
}

sub _ReceiverDelivery {
	my ( $self, %args ) = @_;

	my $headerframe = $self->_LocalReceive(
		channel => $args{channel},
		header_frame => [ 'Net::AMQP::Protocol::Basic::ContentHeader' ],
	);

	my $length = $headerframe->{body_size};
	my $payload = '';

	while( length( $payload ) < $length ) {
		my $frame = $self->_LocalReceive(
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

sub Receive {
	my ( $self, %args ) = @_;

	my $nextframe = $self->_LocalReceive(
		channel => $args{channel},
	);

	if( ref $nextframe eq 'Net::AMQP::Frame::Method' ) {
		my $method_frame = $nextframe->method_frame;

		if( ref $method_frame eq 'Net::AMQP::Protocol::Basic::Deliver' ) {
			return (
				$self->_ReceiverDelivery(
					channel => $nextframe->channel,
				),
				delivery_frame => $nextframe,
			);
		}
	}

	return $nextframe;
}

sub Disconnect {
	my($self, $args ) = @_;

	$self->RabbitRPC(
		channel => 0,
		output => [
			Net::AMQP::Protocol::Connection::Close->new(
			),
		],
		resposnse_type => 'Net::AMQP::Protocol::Connection::CloseOk',
	);

	if( ! $self->_Remote->close() ) {
		Carp::croak "Could not close socket: $OS_ERROR";
	}

	return;
}

sub _Send {
	my ( $self, %args ) = @_;
	my $channel = $args{channel};
	my $output = $args{output};

	if( ref $output ) {
		if ( $output->isa("Net::AMQP::Protocol::Base") ) {
			$output = $output->frame_wrap;
		}

		if( ! defined $output->channel ) {
			$output->channel( $channel )
		}

		$self->_Remote->print( $output->to_raw_frame() );

	}
	else {
		$self->_Remote->print( $output );
	}

	return;
}

sub ChannelOpen {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->RabbitRPC(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Channel::Open->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Channel::OpenOk',
	);
}

sub ExchangeDeclare {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->RabbitRPC(
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

sub ExchangeDelete {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->RabbitRPC(
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

sub QueueDeclare {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return$self->RabbitRPC(
		channel => $channel,
		output => [
			 Net::AMQP::Protocol::Queue::Declare->new(
				queue => $args{queue},
				passive => $args{passive},
				durable => $args{durable},
				exclusive => $args{exclusive},
				arguments => {
					auto_delete => $args{auto_delete},
				}
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::DeclareOk',
	);
}

sub QueueBind {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	return $self->RabbitRPC(
		channel => $channel,
		output => [
			Net::AMQP::Protocol::Queue::Bind->new(
				queue => $args{queue},
				exchange => $args{exchange},
				routing_key => $args{routing_key},
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::BindOk',
	);
}

sub QueuePurge {
	my ( $self, %args ) = @_;


	return $self->RabbitRPC(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Queue::Purge->new(
				queue => $args{queue},
			),
		],
		response_type => 'Net::AMQP::Protocol::Queue::PurgeOk',
	);
}

sub BasicAck {
	my ( $self, %args ) = @_;

	return $self->RabbitRPC(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Basic::Ack->new(
				delivery_tag => $args{delivery_tag},
				multiple => $args{multiple},
			),
		],
	);
}

sub BasicGet {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};

	my $get = $self->RabbitRPC(
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
		return $self->_ReceiverDelivery(
			channel => $channel,
		);
	}
}

sub BasicPublish {
	my ( $self, %args ) = @_;

	my $channel = $args{channel};
	my $payload = $args{payload};

	return $self->RabbitRPC(
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

sub BasicConsume {
	my ( $self, %args ) = @_;

	return $self->RabbitRPC(
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

sub TxSelect {
	my ( $self, %args ) = @_;

	return $self->RabbitRPC(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Tx::Select->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Tx::SelectOk',
	);
}

sub TxCommit {
	my ( $self, %args ) = @_;

	return $self->RabbitRPC(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Tx::Commit->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Tx::CommitOk',
	);
}

sub TxRollback {
	my ( $self, %args ) = @_;

	return $self->RabbitRPC(
		channel => $args{channel},
		output => [
			Net::AMQP::Protocol::Tx::Rollback->new(
			),
		],
		response_type => 'Net::AMQP::Protocol::Tx::RollbackOk',
	);
}

=head1 NAME

Net::AMQP::RabbitMQ - Perl-based RabbitMQ AMQP client

=head1 SYNOPSIS

  use NetRabbitMQPerl;
  blah blah blah


=head1 DESCRIPTION

Stub documentation for this module was created by ExtUtils::ModuleMaker.
It looks like the author of the extension was negligent enough
to leave the stub unedited.

Blah blah blah.


=head1 USAGE



=head1 BUGS



=head1 SUPPORT



=head1 AUTHOR

	Eugene Marcotte
	athenahealth
	emarcotte@athenahealth.com
	http://athenahealth.com

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

perl(1).

=cut

1;
