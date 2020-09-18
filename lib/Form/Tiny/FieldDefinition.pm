package Form::Tiny::FieldDefinition;

use v5.10; use warnings;
use Moo;
use Types::Standard qw(Enum Bool HasMethods CodeRef Maybe Str);
use Types::Common::String qw(NonEmptySimpleStr);
use Carp qw(croak);
use Scalar::Util qw(blessed);

use Form::Tiny::Error;

use namespace::clean;

our $nesting_separator = q{.};
our $array_marker = q{*};

has "name" => (
	is => "ro",
	isa => NonEmptySimpleStr,
	required => 1,
);

has "required" => (
	is => "ro",
	isa => Enum [0, 1, "soft", "hard"],
	default => sub { 0 },
);

has "type" => (
	is => "ro",
	isa => HasMethods ["validate", "check"],
	predicate => 1,
);

has "coerce" => (
	is => "ro",
	isa => Bool | CodeRef,
	default => sub { 0 },
);

has "adjust" => (
	is => "ro",
	isa => CodeRef,
	predicate => "is_adjusted",
	writer => "set_adjustment",
);

has "message" => (
	is => "ro",
	isa => Str,
	predicate => 1,
);

sub BUILD
{
	my ($self, $args) = @_;

	if ($self->coerce && ref $self->coerce ne "CODE") {

		# checks for coercion == 1
		my $t = $self->type;
		croak "the type doesn't provide coercion"
			if !$self->has_type
			|| !($t->can("coerce") && $t->can("has_coercion") && $t->has_coercion);
	}

	if ($self->is_subform && !$self->is_adjusted) {
		$self->set_adjustment(sub { $self->type->fields });
	}
}

sub is_subform
{
	my ($self) = @_;

	return $self->has_type && $self->type->DOES("Form::Tiny::Form");
}

sub get_name_path
{
	my ($self) = @_;

	my $sep = quotemeta $nesting_separator;
	my @parts = split /(?<!\\)$sep/, $self->name;
	return map { s/\\$sep/$nesting_separator/g; $_ } @parts;
}

sub want_array
{
	my ($self) = @_;

	my $sep = quotemeta $nesting_separator;
	my $arr = quotemeta $array_marker;
	return $self->name =~ /$sep $arr ($sep | \z)/x;
}

sub join_path
{
	my ($self, $path) = @_;

	my $sep = quotemeta $nesting_separator;
	@$path = map { s/$sep/\\$nesting_separator/g; $_ } @$path;
	return join $nesting_separator, @$path;
}

sub hard_required
{
	my ($self) = @_;

	return $self->required eq "hard" || $self->required eq "1";
}

sub get_coerced
{
	my ($self, $value) = @_;

	my $coerce = $self->coerce;
	if (ref $coerce eq "CODE") {
		return $coerce->($value);
	}
	elsif ($coerce) {
		return $self->type->coerce($value);
	}
	else {
		return $value;
	}
}

sub get_adjusted
{
	my ($self, $value) = @_;

	if ($self->is_adjusted) {
		return $self->adjust->($value);
	}
	return $value;
}

sub validate
{
	my ($self, $form, $value) = @_;

	# no validation if no type specified
	return 1
		if !$self->has_type;

	my $valid;
	my $error;
	if ($self->has_message) {
		$valid = $self->type->check($value);
		$error = $self->message;
	}
	else {
		$error = $self->type->validate($value);
		$valid = !defined $error;
	}

	if (!$valid) {
		if ($self->is_subform && ref $error eq ref []) {
			foreach my $exception (@$error) {
				if (defined blessed $exception && $exception->isa("Form::Tiny::Error")) {
					$exception->set_field(
						join $nesting_separator,
						$self->name, ($exception->field // ())
					);
				}
				else {
					$exception = Form::Tiny::Error::DoesNotValidate->new({
							field => $self->name,
							error => $exception,
						}
					);
				}

				$form->add_error($exception);
			}
		}
		else {
			my $exception = Form::Tiny::Error::DoesNotValidate->new({
					field => $self->name,
					error => $error,
				}
			);

			$form->add_error($exception);
		}
	}

	return $valid;
}

1;
