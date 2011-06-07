#!perl -T

use Test::More;
use MongoQL qw/update_doc/;
use Try::Tiny;

# start by making sure doc_matches() fails when it needs to:
my $err = try { update_doc() } catch { (m/(.+) at t\/02-updating.t/)[0] };
is($err, 'MongoQL::update_doc() requires a document hash-ref.', 'update_doc() fails when nothing is given.');
undef $err;

$err = try { update_doc('asdf') } catch { (m/(.+) at t\/02-updating.t/)[0] };
is($err, 'MongoQL::update_doc() requires a document hash-ref.', 'update_doc() fails when a scalar is given for a document.');
undef $err;

$err = try { update_doc([1,2,3]) } catch { (m/(.+) at t\/02-updating.t/)[0] };
is($err, 'MongoQL::update_doc() requires a document hash-ref.', 'update_doc() fails when a non-hash reference is given for a document.');
undef $err;

$err = try { update_doc({ asdf => 1 }) } catch { (m/(.+) at t\/02-updating.t/)[0] };
is($err, 'MongoQL::update_doc() requires an update hash-ref.', 'update_doc() fails when no update hash-ref is given.');
undef $err;

$err = try { update_doc({ asdf => 1 }, [1,2,3]) } catch { (m/(.+) at t\/02-updating.t/)[0] };
is($err, 'MongoQL::update_doc() requires an update hash-ref.', 'update_doc() fails when a non-hash reference is given for the update.');
undef $err;

# let's make sure that when the update hash-ref has no advanced operators
# the update object is returned as the new document
is_deeply(update_doc({ asdf => 1 }, { title => 'kick it', you_gotta => 'fight' }), { title => 'kick it', you_gotta => 'fight' }, 'replacement update works');

# let's check update operators one by one
# 1. $inc
is_deeply(update_doc({ number => 12 }, { '$inc' => { number => 2 } }), { number => 14 }, '$inc works');

# 2. $set
is_deeply(update_doc({ something => 'regular', cow => 'bell' }, { '$set' => { something => 'different', nothing => 'else' } }), { something => 'different', nothing => 'else', cow => 'bell' }, '$set works');

# 4. $unset
is_deeply(update_doc({ something => 'regular' }, { '$unset' => { something => 1 } }), {}, '$unset works');

# 5. $rename
is_deeply(update_doc({ wrong_key => 'correct_value' }, { '$rename' => { wrong_key => 'correct_key' } }), { correct_key => 'correct_value' }, '$rename works');

# 6. $push
is_deeply(update_doc({ array => [1] }, { '$push' => { array => 2 } }), { array => [1,2] }, '$push works');

# 7. $pushAll
is_deeply(update_doc({ array => [1] }, { '$pushAll' => { array => [2,3] } }), { array => [1 .. 3] }, '$pushAll works');

# 8. $addToSet
is_deeply(update_doc({ array => [qw/one two three/] }, { '$addToSet' => { array => 'two' } }), { array => [qw/one two three/] }, '$addToSet works');
is_deeply(update_doc({ array => [qw/one two three/] }, { '$addToSet' => { array => [qw/two four six/] } }), { array => [qw/one two three four six/] }, '$addToSet works');

# 9. $pop
is_deeply(update_doc({ array => [1 .. 5] }, { '$pop' => { array => 1 } }), { array => [2 .. 5] }, '$pop #1 works');
is_deeply(update_doc({ array => [1 .. 5] }, { '$pop' => { array => -1 } }), { array => [1 .. 4] }, '$pop #2 works');
is_deeply(update_doc({ array => [1 .. 5] }, { '$pop' => { array => 2 } }), { array => [1,2,4,5] }, '$pop  #3 works');

# 10. $pull
is_deeply(update_doc({ array => [qw/sex drugs rocknroll/] }, { '$pull' => { array => 'sex' } }), { array => [qw/drugs rocknroll/] }, '$pull works');

# 11. $pullAll
is_deeply(update_doc({ array => [qw/sex drugs rocknroll/] }, { '$pullAll' => { array => [qw/sex drugs/] } }), { array => [qw/rocknroll/] }, '$pullAll works');

done_testing();
