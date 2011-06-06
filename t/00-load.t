#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'MongoQL' ) || print "Bail out!\n";
}

diag( "Testing MongoQL $MongoQL::VERSION, Perl $], $^X" );
