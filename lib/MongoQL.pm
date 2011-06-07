package MongoQL;

# ABSTRACT: MongoDB-style query and update language for any purpose

BEGIN {
	use Exporter 'import';
	@EXPORT_OK = qw/doc_matches update_doc/;
}

use warnings;
use strict;

use Carp;
use Data::Compare;
use Data::Types qw/:is/;
use DateTime::Format::W3CDTF;
use Scalar::Util qw/blessed/;
use Try::Tiny;

our $VERSION = "0.001";
$VERSION = eval $VERSION;

=head1 NAME

MongoQL - MongoDB-style query and update language for any purpose

=head1 SYNOPSIS

	use MongoQL qw/doc_matches update_doc/;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.

=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.

=head1 INTERFACE

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.

=head2 doc_matches( \%document, [ \%query ] )

=cut

sub doc_matches {
	my ($doc, $query) = @_;

	croak "MongoQL::doc_matches() requires a document hash-ref."
		unless $doc && ref $doc && ref $doc eq 'HASH';
	croak "MongoQL::doc_matches() expects a query hash-ref."
		if $query && (!ref $query || (ref $query && ref $query ne 'HASH'));

	$query ||= {};

	# go over each key of the query
	foreach my $key (keys %$query) {
		my $value = $query->{$key};
		if ($key eq '$or' && ref $value eq 'ARRAY') {
			my $found;
			foreach (@$value) {
				next unless ref $_ eq 'HASH';
				my $ok = 1;
				while (my ($k, $v) = each %$_) {
					unless (&_attribute_matches($doc, $k, $v)) {
						undef $ok;
						last;
					}
				}
				if ($ok) { # document matches this criteria
					$found = 1;
					last;
				}
			}
			return unless $found;
		} else {
			return unless &_attribute_matches($doc, $key, $value);
		}
	}

	# if we've reached here, the document matches, so return true
	return 1;
}

=head2 update_doc( \%document, \%update )

=cut

sub update_doc {
	my ($doc, $obj) = @_;

	croak "MongoQL::update_doc() requires a document hash-ref."
		unless defined $doc && ref $doc && ref $doc eq 'HASH';
	croak "MongoQL::update_doc() requires an update hash-ref."
		unless defined $obj && ref $obj && ref $obj eq 'HASH';

	# we only need to do something if the $obj hash-ref has any advanced
	# update operations, otherwise $obj is meant to be the new $doc

	if (&_has_adv_upd($obj)) {
		foreach my $op (keys %$obj) {
			next if $_ eq '_name';
			if ($op eq '$inc') {
				# increase numerically
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					$doc->{$field} ||= 0;
					$doc->{$field} += $obj->{$op}->{$field};
				}
			} elsif ($op eq '$set') {
				# set key-value pairs
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					$doc->{$field} = $obj->{$op}->{$field};
				}
			} elsif ($op eq '$unset') {
				# remove key-value pairs
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					delete $doc->{$field} if $obj->{$op}->{$field};
				}
			} elsif ($op eq '$push') {
				# push values to end of arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, $obj->{$op}->{$field});
				}
			} elsif ($op eq '$pushAll') {
				# push a list of values to end of arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, @{$obj->{$op}->{$field}});
				}
			} elsif ($op eq '$addToSet') {
				# push values to arrays only if they're not already there
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					push(@{$doc->{$field}}, $obj->{$op}->{$field})
						unless defined &_index_of($obj->{$op}->{$field}, $doc->{$field});
				}
			} elsif ($op eq '$pop') {
				# pop values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					splice(@{$doc->{$field}}, $obj->{$op}->{$field}, 1);
				}
			} elsif ($op eq '$rename') {
				# rename attributes
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					$doc->{$obj->{$op}->{$field}} = delete $doc->{$field}
						if exists $doc->{$field};
				}
			} elsif ($op eq '$pull') {
				# remove values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					my $i = &_index_of($obj->{$op}->{$field}, $doc->{$field});
					while (defined $i) {
						splice(@{$doc->{$field}}, $i, 1);
						$i = &_index_of($obj->{$op}->{$field}, $doc->{$field});
					}
				}
			} elsif ($op eq '$pullAll') {
				# remove a list of values from arrays
				next unless ref $obj->{$op} eq 'HASH';
				foreach my $field (keys %{$obj->{$op}}) {
					croak "The $field attribute is not an array in $doc->{_name}."
						if defined $doc->{$field} && ref $doc->{$field} ne 'ARRAY';
					$doc->{$field} ||= [];
					foreach my $value (@{$obj->{$op}->{$field}}) {
						my $i = &_index_of($value, $doc->{$field});
						while (defined $i) {
							splice(@{$doc->{$field}}, $i, 1);
							$i = &_index_of($value, $doc->{$field});
						}
					}
				}
			}
		}
	} else {
		# $obj is actually the new $doc
		foreach (keys %$obj) {
			next if $_ eq '_name';
			$doc->{$_} = $obj->{$_};
		}
	}
}

sub _attribute_matches {
	my ($doc, $key, $value) = @_;

	if (!ref $value) {		# if value is a scalar, we need to check for equality
					# (or, if the attribute is an array in the document,
					# we need to check the value exists in it)
		return unless $doc->{$key};
		if (ref $doc->{$key} eq 'ARRAY') { # check the array has the requested value
			return unless &_array_has_eq($value, $doc->{$key});
		} elsif (!ref $doc->{$key}) { # check the values are equal
			return unless $doc->{$key} eq $value;
		} else { # we can't compare a non-scalar to a scalar, so return false
			return;
		}
	} elsif (ref $value eq 'Regexp') {	# if the value is a regex, we need to check
						# for a match (or, if the attribute is an array
						# in the document, we need to check at least one
						# value in it matches it)
		return unless $doc->{$key};
		if (ref $doc->{$key} eq 'ARRAY') {
			return unless &_array_has_re($value, $doc->{$key});
		} elsif (!ref $doc->{$key}) { # check the values match
			return unless $doc->{$key} =~ $value;
		} else { # we can't compare a non-scalar to a scalar, so return false
			return;
		}
	} elsif (ref $value eq 'HASH') { # if the value is a hash, than it either contains
					 # advanced queries, or it's just a hash that we
					 # want the document to have as-is
		unless (&_has_adv_que($value)) {
			# value hash-ref doesn't have any advanced
			# queries, we need to check our document
			# has an attributes with exactly the same hash-ref
			# (and name of course)
			return unless Compare($value, $doc->{$key});
		} else {
			# value contains advanced queries,
			# we need to make sure our document has an
			# attribute with the same name that matches
			# all these queries
			foreach my $q (keys %$value) {
				my $term = $value->{$q};
				if ($q eq '$gt') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if (is_float($doc->{$key})) {
						return unless $doc->{$key} > $term;
					} else {
						return unless $doc->{$key} gt $term;
					}
				} elsif ($q eq '$gte') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if (is_float($doc->{$key})) {
						return unless $doc->{$key} >= $term;
					} else {
						return unless $doc->{$key} ge $term;
					}
				} elsif ($q eq '$lt') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if (is_float($doc->{$key})) {
						return unless $doc->{$key} < $term;
					} else {
						return unless $doc->{$key} lt $term;
					}
				} elsif ($q eq '$lte') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if (is_float($doc->{$key})) {
						return unless $doc->{$key} <= $term;
					} else {
						return unless $doc->{$key} le $term;
					}
				} elsif ($q eq '$eq') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if (is_float($doc->{$key})) {
						return unless $doc->{$key} == $term;
					} else {
						return unless $doc->{$key} eq $term;
					}
				} elsif ($q eq '$ne') {
					return unless defined $doc->{$key} && !ref $doc->{$key};
					if (is_float($doc->{$key})) {
						return unless $doc->{$key} != $term;
					} else {
						return unless $doc->{$key} ne $term;
					}
				} elsif ($q eq '$exists') {
					if ($term) {
						return unless exists $doc->{$key};
					} else {
						return if exists $doc->{$key};
					}
				} elsif ($q eq '$mod' && ref $term eq 'ARRAY' && scalar @$term == 2) {
					return unless defined $doc->{$key} && is_float($doc->{$key}) && $doc->{$key} % $term->[0] == $term->[1];
				} elsif ($q eq '$in' && ref $term eq 'ARRAY') {
					return unless defined $doc->{$key} && &_value_in($doc->{$key}, $term);
				} elsif ($q eq '$nin' && ref $term eq 'ARRAY') {
					return unless defined $doc->{$key} && !&_value_in($doc->{$key}, $term);
				} elsif ($q eq '$size' && is_int($term)) {
					return unless defined $doc->{$key} && ((ref $doc->{$key} eq 'ARRAY' && scalar @{$doc->{$key}} == $term) || (ref $doc->{$key} eq 'HASH' && scalar keys %{$doc->{$key}} == $term));
				} elsif ($q eq '$all' && ref $term eq 'ARRAY') {
					return unless defined $doc->{$key} && ref $doc->{$key} eq 'ARRAY';
					foreach (@$term) {
						return unless &_value_in($_, $doc->{$key});
					}
				} elsif ($q eq '$type' && !ref $term) {
					if ($term eq 'int') {
						return unless defined $doc->{$key} && is_int($doc->{$key});
					} elsif ($term eq 'float') {
						return unless defined $doc->{$key} && is_float($doc->{$key});
					} elsif ($term eq 'real') {
						return unless defined $doc->{$key} && is_real($doc->{$key});
					} elsif ($term eq 'whole') {
						return unless defined $doc->{$key} && is_whole($doc->{$key});
					} elsif ($term eq 'string') {
						return unless defined $doc->{$key} && is_string($doc->{$key});
					} elsif ($term eq 'array') {
						return unless defined $doc->{$key} && ref $doc->{$key} eq 'ARRAY';
					} elsif ($term eq 'hash') {
						return unless defined $doc->{$key} && ref $doc->{$key} eq 'HASH';
					} elsif ($term eq 'bool') {
						# boolean - not really supported, will always return true since everything in Perl is a boolean
					} elsif ($term eq 'date') {
						return unless defined $doc->{$key} && !ref $doc->{$key};
						my $date = try { DateTime::Format::W3CDTF->parse_datetime($doc->{$key}) } catch { undef };
						return unless blessed $date && blessed $date eq 'DateTime';
					} elsif ($term eq 'null') {
						return unless exists $doc->{$key} && !defined $doc->{$key};
					} elsif ($term eq 'regex') {
						return unless defined $doc->{$key} && ref $doc->{$key} eq 'Regexp';
					}
				}
			}
		}
	}

	return 1;
}

=head2 _array_has_eq( $value, \@array )

Returns a true value if the provided array reference holds the scalar
value C<$value>.

=cut

sub _array_has_eq {
	my ($value, $array) = @_;

	foreach (@$array) {
		return 1 if $_ eq $value;
	}

	return;
}

=head2 _array_has_re( $regex, \@array )

Returns a true valie if the provided array reference holds a scalar value
that matches the provided regular expression.

=cut

sub _array_has_re {
	my ($re, $array) = @_;

	foreach (@$array) {
		return 1 if m/$re/;
	}

	return;
}

=head2 _has_adv_que( \%hash )

Returns a true value if the provided hash-ref holds advanced queries (like
C<$gt>, C<$exists>, etc.).

=cut

sub _has_adv_que {
	my $hash = shift;

	foreach ('$gt', '$gte', '$lt', '$lte', '$all', '$exists', '$mod', '$eq', '$ne', '$in', '$nin', '$size', '$type') {
		return 1 if exists $hash->{$_};
	}

	return;
}

=head2 _value_in( $value, \@array )

Returns a true value if the variable C<$value> is one of the items in C<\@array>.

=cut

sub _value_in {
	my ($value, $array) = @_;

	foreach (@$array) {
		next if is_float($_) && !is_float($value);
		next if !is_float($_) && is_float($value);
		return 1 if is_float($_) && $value == $_;
		return 1 if !is_float($_) && $value eq $_;
	}

	return;
}

=head2 _has_adv_upd( \%hash )

Returns a true value if the provided hash-ref has advanced update operations
like C<$inc>, C<$push>, etc.

=cut

sub _has_adv_upd {
	my $hash = shift;

	foreach ('$inc', '$set', '$unset', '$push', '$pushAll', '$addToSet', '$pop', '$pull', '$pullAll', '$rename', '$bit') {
		return 1 if exists $hash->{$_};
	}

	return;
}

=head2 _index_of( $value, \@array )

Returns the index of C<$value> in the array reference, if it exists there,
otherwise returns C<undef>.

=cut

sub _index_of {
	my ($value, $array) = @_;

	for (my $i = 0; $i < scalar @$array; $i++) {
		next if is_float($array->[$i]) && !is_float($value);
		next if !is_float($array->[$i]) && is_float($value);
		return $i if is_float($array->[$i]) && $value == $array->[$i];
		return $i if is_float($array->[$i]) && $value eq $array->[$i];
	}

	return;
}

=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back

=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
MongoQL requires no configuration files or environment variables.

=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.

=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.

=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-MongoQL@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=MongoQL>.

=head1 AUTHOR

Ido Perlmuter <ido at ido50 dot net>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, Ido Perlmuter C<< ido at ido50 dot net >>.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself, either version
5.8.1 or any later version. See L<perlartistic|perlartistic> 
and L<perlgpl|perlgpl>.

The full text of the license can be found in the
LICENSE file included with this module.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

=cut

1;
__END__
