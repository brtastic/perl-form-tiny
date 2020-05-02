package Form::Tiny;

use Modern::Perl "2010";
use Types::Standard qw(Str Maybe ArrayRef InstanceOf HashRef Bool CodeRef);
use Carp qw(croak);
use Storable qw(dclone);

use Form::Tiny::FieldDefinition;
use Form::Tiny::Error;
use Moo::Role;
use Sub::HandlesVia;

our $VERSION = '1.00';

requires qw(build_fields);

has "field_defs" => (
	is => "rw",
	isa => ArrayRef[
		(InstanceOf["Form::Tiny::FieldDefinition"])
			->plus_coercions(HashRef, q{ Form::Tiny::FieldDefinition->new($_) })
	],
	coerce => 1,
	default => sub {
		[ shift->build_fields ]
	},
	trigger => \&_clear_form,
);

has "input" => (
	is => "rw",
	writer => "set_input",
	trigger => \&_clear_form,
);

has "fields" => (
	is => "rw",
	isa => Maybe[HashRef],
	writer => "_set_fields",
	clearer => "_clear_fields",
	init_arg => undef,
);

has "valid" => (
	is => "ro",
	isa => Bool,
	writer => "_set_valid",
	lazy => 1,
	builder => "_validate",
	clearer => 1,
	predicate => "is_validated",
	init_arg => undef,
);

has "errors" => (
	is => "ro",
	isa => ArrayRef[InstanceOf["Form::Tiny::Error"]],
	default => sub { [] },
	init_arg => undef,
	handles_via => "Array",
	handles => {
		"add_error" => "push",
		"has_errors" => "count",
		"_clear_errors" => "clear",
	},
);

has "cleaner" => (
	is => "rw",
	isa => Maybe[CodeRef],
	default => sub {
		shift->can("build_cleaner");
	},
);

around BUILDARGS => sub {
	my ($orig, $class, @args) = @_;

	return {input => @args}
		if @args == 1;

	return {@args};
};

sub _clear_form {
	my ($self) = @_;

	$self->_clear_fields;
	$self->clear_valid;
	$self->_clear_errors;
}

sub _pre_mangle {}
sub _pre_validate {}

sub _mangle_field
{
	my ($self, $def, $current) = @_;

	# if the parameter is required (hard), we only consider it if not empty
	if (!$def->hard_required || ref $$current || length($$current // "")) {

		# coerce, validate, adjust
		$$current = $def->get_coerced($$current);
		if ($def->validate($self, $$current)) {
			$$current = $def->get_adjusted($$current);
		}
		return 1;
	}
	return 0;
}

sub _find_field
{
	my ($self, $fields, $field_def) = @_;

	my @parts = $field_def->get_name_path;
	my $current = $fields;
	for my $i (0 .. $#parts) {
		last unless ref $current eq ref {} && exists $current->{$parts[$i]};

		if ($i == $#parts) {
			return \$current->{$parts[$i]};
		} else {
			$current = $current->{$parts[$i]};
		}
	}

	return;
}

sub _assign_field
{
	my ($self, $fields, $field_def, $val_ref) = @_;

	my @parts = $field_def->get_name_path;
	my $current = $fields;
	for my $i (0 .. $#parts) {
		if ($i == $#parts) {
			$current->{$parts[$i]} = $$val_ref;
			return \$current->{$parts[$i]};
		} else {
			$current->{$parts[$i]} //= {};
			$current = $current->{$parts[$i]};
		}
	}
}

sub _validate
{
	my ($self) = @_;
	my $dirty = {};
	$self->_clear_errors;

	if (ref $self->input eq ref {}) {
		my $fields = dclone($self->input);
		$self->_pre_validate($fields);
		foreach my $validator (@{$self->field_defs}) {
			my $curr_f = $validator->name;

			my $current = $self->_find_field($fields, $validator);
			if (defined $current) {

				$current = $self->_assign_field($dirty, $validator, $current);
				$self->_pre_mangle($validator, $current);

				# found and valid, go to the next field
				next if $self->_mangle_field($validator, $current);
			}

			# for when it didn't pass the existence test
			if ($validator->required) {
				$self->add_error(Form::Tiny::Error::DoesNotExist->new(field => $curr_f));
			}
		}
	} else {
		$self->add_error(Form::Tiny::Error::InvalidFormat->new);
	}

	$dirty = $self->cleaner->($self, $dirty)
		if defined $self->cleaner && !$self->has_errors;

	my $form_valid = !$self->has_errors;
	$self->_set_fields($form_valid ? $dirty : undef);

	return $form_valid;
}

sub check
{
	my ($self, $input) = @_;

	$self->set_input($input);
	return $self->valid;
}

sub validate
{
	my ($self, $input) = @_;

	return if $self->check($input);
	return $self->errors;
}

1;

__END__

=head1 NAME

Form::Tiny - Tiny form implementation centered around Type::Tiny

=head1 SYNOPSIS

	use Moo;
	use Types::Common::String qw(SimpleStr);
	use Types::Common::Numeric qw(PositiveInt);

	with "Form::Tiny";

	sub build_fields {
		{
			name => "name",
			type => SimpleStr,
			adjust => sub { ucfirst shift },
			required => 1,
		},
		{
			name => "lucky_number",
			type => PositiveInt,
			required => 1,
		}
	}

	sub build_cleaner {
		my ($self, $data) = @_;

		if ($data->{name} eq "Perl" && $data->{lucky_number} == 6) {
			$self->add_error(Form::Tiny::Error::DoesNotValidate->new("Perl6 is Raku"));
		}

		return $data;
	}

=head1 DESCRIPTION

Form validation engine that can reuse all the type constraints you're already familiar with.

=head1 FORM BUILDING

Every class applying the I<Form::Tiny> role has to have a sub called I<build_fields>. This method should return a list of hashrefs, where each of them will be coerced into an object of the L<Form::Tiny::FieldDefinition> class.

The only required element of this hashref is I<name>, which contains the string name of the field in the form input. Other possible elements are:

=over

=item type

A type that the field will be validated against. Effectively, this needs to be an object with I<validate> and I<check> methods.

=item coerce

A coercion that will be made B<before> the type is validated and will change the value of the field. This can be a coderef or a boolean:

Value of I<1> means that coercion will be applied from the specified I<type>. This requires the type to also provide I<coerce> and I<has_coercion> method, and the return value of the second one must be true.

Value of I<0> means no coercion will be made.

Value that is a coderef will be passed a single scalar, which is the value of the field. It is required to make its own checks and return a scalar which will replace the old value.

=item adjust

An adjustment that will be made B<after> the type is validated and the validation is successful. This must be a coderef that gets passed the validated value and returns the new value for the field.

=item required

Controls if the field should be skipped silently if it has no value or the value is empty. Possible values are:

I<0> - The field can be non-existent in the input, empty or undefined

I<"soft"> - The field has to exist in the input, but can be empty or undefined

I<1> or I<"hard"> - The field has to exist in the input, must be defined and non-empty (value of I<0> is allowed)

=item message

A static string that should be output instead of an error message returned by the I<type> when the validation fail.

=back
