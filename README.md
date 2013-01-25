Net::AMQP::RabbitMQ
---------------

# Build

Building the module should be straightforward.

	# Generate the build script
	perl Build.PL

	# Build the module
	./Build

	# Run the tests
	./Build test

	# Install the module
	./Build install

# Tests

The tests in this library are based on those found in Net::RabbitMQ.

If you are stuck in an environment where you cannot reach the internet you can
still run tests by exporting MQHOST to some accessible instance.
