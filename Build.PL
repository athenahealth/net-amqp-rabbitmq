use Module::Build;
# See perldoc Module::Build for details of how this works

my $build = Module::Build->new(
	module_name     => 'Net::AMQP::RabbitMQ',
	license         => 'perl',
	dist_abstract   => "Pure perl AMQP client for RabbitMQ",

	requires => {
		'Net::AMQP' => 0.06,
		'List::MoreUtils' => 0.25,
		'File::ShareDir' => 1.00,
	},

	recommends => {
		# Allows TCP keep alive functionality to work
		'Socket::Linux' => 0.01,
	},

	build_requires => {
		'Test::Exception' => 0.24,
	},

	configure_requires => {
		'Module::Build' => 0.40,
	},

	create_makefile_pl => 'passthrough',

	share_dir => 'share'
);

$build->create_build_script;
