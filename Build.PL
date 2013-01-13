use Module::Build;
# See perldoc Module::Build for details of how this works

my $build = Module::Build->new(
	module_name     => 'Net::AMQP::RabbitMQ',
	license         => 'perl',
	dist_abstract   => "Pure perl AMQP client for RabbitMQ",

	requires => {
		'Net::AMQP' => 0.05,
	},


	share_dir => 'share'
);

$build->create_build_script;
