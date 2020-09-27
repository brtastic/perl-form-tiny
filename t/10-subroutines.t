use v5.10; use warnings;
use Test::More;
use Data::Dumper;
use Form::Tiny;

{

	package TestForm;
	use Moo;
	use Types::Standard qw(Str);

	with "Form::Tiny";

	sub build_fields
	{
		(
			{
				name => "sub_based",
				type => Str->where(q{ /\A0x[0-9a-fA-F]+\z/ }),

				coerce => sub {
					my $val = shift;
					if (defined $val && $val =~ /\A[0-9]+\z/) {
						return "0x" . sprintf("%x", $val);
					}
					return $val;
				},

				adjust => sub {
					return lc shift;
				},
			}
		)
	}

	1;
}

my @data = (

	# validated
	[1, {sub_based => "0x33333c"}],
	[1, {sub_based => "0xfab5"}],
	[0, {sub_based => "0xxfab5"}],
	[0, {sub_based => "-0xfab5"}],
	[0, {sub_based => ""}],
	[0, {sub_based => undef}],

	# coerced
	[1, {sub_based => 0x5}, {sub_based => "0x5"}],
	[1, {sub_based => 0x0}, {sub_based => "0x0"}],
	[1, {sub_based => 0xaa}, {sub_based => "0xaa"}],
	[0, {sub_based => "-0"}],
	[0, {sub_based => "-1"}],
	[0, {sub_based => "123456789_"}],

	# adjusted
	[1, {sub_based => "0xA"}, {sub_based => "0xa"}],
	[1, {sub_based => "0xF32C"}, {sub_based => "0xf32c"}],
);

for my $aref (@data) {
	my ($result, $input, $output) = @$aref;
	$output //= $input;

	my $form = TestForm->new($input);
	is !!$form->valid, !!$result, "validation output ok";

	if ($form->valid) {
		for my $field (keys %$output) {
			is defined $form->fields->{$field}, defined $output->{$field},
				"definedness for `$field` ok";
			is $form->fields->{$field}, $output->{$field}, "value for `$field` ok";
		}
	}
	elsif ($result) {
		note Dumper($form->dirty_fields);
	}
}

done_testing();