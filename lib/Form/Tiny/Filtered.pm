package Form::Tiny::Filtered;

use v5.10;
use warnings;
use Types::Standard qw(Str ArrayRef InstanceOf);

use Form::Tiny::Filter;
use Form::Tiny::Utils qw(trim);
use Moo::Role;

our $VERSION = '1.13';

requires qw(setup);

has "filters" => (
	is => "ro",
	isa => ArrayRef [
		InstanceOf ["Form::Tiny::Filter"]
	],
	coerce => 1,
	default => sub {
		my ($self) = @_;
		[Str, sub { trim(@_) }],
	},
);

sub add_filter
{
	my ($self, $type, $code) = @_;

	push @{$self->filters}, Form::Tiny::Filter->new(
		type => $type,
		code => $code
	);
}

sub _apply_filters
{
	my ($self, $obj, $value) = @_;

	for my $filter (@{$self->filters}) {
		$value = $filter->filter($value);
	}

	return $value;
}

after 'inherit_from' => sub {
	my ($self, $parent) = @_;

	if ($parent->DOES('Form::Tiny::Filtered')) {
		$self->filters([@{$parent->filters}, @{$self->filters}]);
	}
};

after 'setup' => sub {
	my ($self) = @_;

	$self->add_hook(before_mangle => sub { $self->_apply_filters(@_) });
};

1;

__END__

=head1 NAME

Form::Tiny::Filtered - early filtering for form fields

=head1 SYNOPSIS

	# in your form class
	use Form::Tiny -filtered;

	# optional - only trims strings by default
	form_filter Int, sub { abs shift() };

=head1 DESCRIPTION

This is a role which is meant to be mixed in together with L<Form::Tiny> role. Having the filtered role enriches Form::Tiny by adding a filtering mechanism which can change the field value before it gets validated.

The filtering system is designed to perform a type check on field values and only apply a filtering subroutine when the type matches.

By default, adding this role to a class will cause all string to be filtered with C<< Form::Tiny::Filtered->trim >>. Specifying the I<build_filters> method explicitly will override that behavior.

=head1 ADDED INTERFACE

=head2 ATTRIBUTES

=head3 filters

Stores an array reference of L<Form::Tiny::Filter> objects, which are used during filtering.

B<writer:> I<set_filters>

=head2 METHODS

=head3 trim

Built in trim functionality, to avoid dependencies. Returns its only argument trimmed.

=head3 build_filters

Just like build_fields, this method should return an array of elements.

Each of these elements should be an instance of Form::Tiny::Filter or an array reference, in which the first element is the type and the second element is the filtering code reference.
