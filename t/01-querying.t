#!perl -T

use Test::More tests => 10;
use MongoQL qw/doc_matches/;
use Try::Tiny;

# start by making sure doc_matches() fails when it needs to:
my $err = try { doc_matches() } catch { (m/(.+) at t\/01-querying.t/)[0] };
is($err, 'MongoQL::doc_matches() requires a document hash-ref.', 'doc_matches() fails when no document is given.');
undef $err;

$err = try { doc_matches('asdf') } catch { (m/(.+) at t\/01-querying.t/)[0] };
is($err, 'MongoQL::doc_matches() requires a document hash-ref.', 'doc_matches() fails when a scalar is given for a document.');
undef $err;

$err = try { doc_matches([1,2,3]) } catch { (m/(.+) at t\/01-querying.t/)[0] };
is($err, 'MongoQL::doc_matches() requires a document hash-ref.', 'doc_matches() fails when a non-hash reference is given for a document.');
undef $err;

$err = try { doc_matches({ asdf => 1 }, 1) } catch { (m/(.+) at t\/01-querying.t/)[0] };
is($err, 'MongoQL::doc_matches() expects a query hash-ref.', 'doc_matches() fails when a scalar is given for the query.');
undef $err;

$err = try { doc_matches({ asdf => 1 }, [1,2,3]) } catch { (m/(.+) at t\/01-querying.t/)[0] };
is($err, 'MongoQL::doc_matches() expects a query hash-ref.', 'doc_matches() fails when a non-hash reference is given for the query.');
undef $err;

# let's make sure every document will match an empty query
ok(doc_matches({ asdf => 1 }), 'doc_matches() returns true when no query is given.');
ok(doc_matches({ one => 1, two => 2 }, {}), 'doc_matches() returns true when an empty query is given.');

# let's get to actual querying and start with simple equality and regex checks
ok(doc_matches({ string => 'yo yo', integer => 123 }, { string => 'yo yo' }), 'simple equality works');
ok(doc_matches({ string => 'my name is nobody' }, { string => qr/nobody$/ }), 'simple regex works');

# now let's take a look at non-equality and $eq-style equality
ok(doc_matches({ should_eq => 'clint', should_not_eq => 'westwood' }, { should_eq => { '$eq' => 'clint' }, should_not_eq => { '$ne' => 'eastwood' } }), 'simple non-equality works');

done_testing();
