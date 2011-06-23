
use strict;
use warnings;
package State::Transition;
# ABSTRACT: Kind of a state-machine

=head1 SYNOPSIS

    use State::Transition;

    my $tran = State::Transition->new(
        counters => 'counter1 ...',
        flags    => 'flag1 ...',
        rules    => {
            'counter1' => { enter => \&enter1 },
            'flag1'    => { leave => \&leave1 },
            ''         => { enter => \&enter2, leave => \&leave2 },
        },
    );

    $tran->work('counter1'); # execute enter1() and leave2()
    ...
    $tran->work('counter1');
    ...
    $tran->work('counter1 flag1');
    ...
    $tran->work('flag1');
    ...
    $tran->done('counter1 flag1'); # execute leave1()
    ...
    $tran->done('counter1') for 1..2; # execute enter2()
    ...

=head1 DESCRIPTION

This module is for managing events when entering or leaving states.
You define states with simple rules (counter, flags, ...) and say which
callback should be executed when entering and/or leaving that state.

=cut

=head1 METHODS

=over 4

=item $tran = B<new> State::Transition key => value...

The constructor supports these arguments (all as C<< key => value >> pairs).

=over 4

=item rules => { 'state1 ...' => { enter => sub {...}, leave => sub {...} } }

Here you can define the rules (state combinations). Allowed are combinations
of every single state (counters, flags, ... seperated by spaces). If there are
more then one state in a rule, it will be and-associated. In every rule a state
has to be unique. You can also pass function names as callbacks, in that case
the object has to support this ($tran->$callback() will be called, use base 'State::Transition' in your class).

Some examples

=over 4

=item 'counter' => ...

The simplest form. Enabled when counter is > 0, disabled when counter == 0. Negative values are not allowed.

=item '+counter' => ...

The same as 'counter'.

=item 'counter:1..*' => ...

The same as 'counter'.

=item '-counter' => ...

Inverts the meaning of '+counter'.

=item 'counter:12' => ...

Only enabled when counter is 12, all other values disable that state.

=item 'counter:4..8' => ...

Only enabled when counter is between 4 and 8, all other values disable that state.

=item '-counter:4..8' => ...

Only enabled when counter is not between 4 and 8, all other values disable that state.

=item 'counter:4..8,12,16..20' => ...

You can define multiple ranges seperated with a comma. 

=item 'flag' => ...

Simple on/off state.

=item 'enum' => ...

Enabled when the enum has his default value.

=item '-enum' => ...

Enabled when the enum has not his default value.

=item 'enum:off,auto' => ...

Enabled when the current value is one of the args.

=item 'counter:12 -flag -enum:auto' => ...

State will be active when counter == 12, flag is off and enum is not auto.

=back

=item counters => '...'

Counters are simple positive integers as a state. At a rule you can use them without argument, that means 0 = off and >0 = on or with a integer (counter:12) or with a range (counter1:4..8) or a combination of all those (counter:12,4..8).

=item flags   => '...'

Flags are only on/off states. You can multiple times work on that state and a
single done will finish that. Another finish will do nothing at all.

=item enums   => '...'

Enums are multivalue flags. A call to done() will do the same then a call to
work(). You always have to submit the new value like 'enum:off'. At a rule you
can use them without argument, that means the enum is at his default (first value).

=item initial => '...'

Here you can define the initial state of the object. Defaults to an empty string (''), that means every defined counter is 0, every defined flag is off and every defined enum is at default.

=back

=cut

sub new {
    my ($class, %args) = @_;

    my $self = bless({
        _states => {
            _counters => {},
            _flags    => {},
            _enums    => {},
            _rules    => {},
        },
        _events => {
            _enter => {},
            _leave => {},
        },
        _enums  => {},
        _test   => '',
    }, $class);


    foreach my $counter (split(/ /, $args{counters} || '')) {
        $self->{_types}{$counter} = 'counter';
        $self->{_states}{_counter}{$counter} = 0;
    }
    foreach my $flag (split(/ /, $args{flags} || '')) {
        $self->{_types}{$flag} = 'flag';
        $self->{_states}{_flags}{$flag} = 0;
    }
    foreach my $enum (split(' ', $args{enums} || '')) {
        my ($name, @types) = split(/[:,]/, $enum);
        die('Enum defined with less then 2 types') if @types < 2;
        $self->{_types}{$name} = 'enum';
        $self->{_enums}{$name}{default}   = $types[0];
        $self->{_enums}{$name}{types}{$_} = 1 for @types;
        $self->{_states}{_enums}{$name} = $types[0];
    }
    foreach my $rule (keys(%{$args{rules}})) {
        $self->{_events}{_enter}{$rule} = $args{rules}{$rule}{enter};
        $self->{_events}{_leave}{$rule} = $args{rules}{$rule}{leave};
        $self->{_states}{_rules}{$rule} = 0;

        $self->_rule2test($rule);
    }
    $self->_compile_test();

    if ($args{initial}) {
        $self->_change($_,1) for $self->_string2states($args{initial});
    }
    $self->_test(0);

    return $self;
}

sub _quote {
    my ($self, $string) = @_;
    $string =~ s/\\/\\\\/g;
    $string =~ s/\'/\\\'/g;
    return $string;
}

sub _rule2test {
    my ($self, $rule) = @_;

    my @tests1;
    foreach my $state ($self->_string2states($rule)) {
        my $negate = $state->{negate} ? '!' : '';
        my $name   = $state->{name};
        my $args   = $state->{args};
        if ($state->{type} eq 'counter') {
            $args //= '1..*';
            my @tests2;
            foreach my $arg (ref($args) ? @$args : $args) {
                if ($arg =~ /^(\d+)\.\.(\d+)$/a) {
                    push(@tests2, sprintf(
                        '$self->{_states}{_counter}{\'%1$s\'} >= %2$d'.
                        ' && $self->{_states}{_counter}{\'%1$s\'} <= %3$d',
                        $self->_quote($name),
                        $1,
                        $2,
                    ));
                }
                elsif ($arg =~ /^(\d+)\.\.\*$/a) {
                    push(@tests2, sprintf(
                        '$self->{_states}{_counter}{\'%1$s\'} >= %2$d',
                        $self->_quote($name),
                        $1,
                    ));
                }
                elsif ($arg =~ /^(\d+)$/) {
                    push(@tests2, sprintf(
                        '$self->{_states}{_counter}{\'%1$s\'} == %2$d',
                        $self->_quote($name),
                        $1,
                    ));
                }
                else {
                    die("Arg $arg not valid for counter $name");
                }
            }
            push(@tests1, $negate.'('.join(' || ', @tests2).')');
        }
    }
    die("No tests for rule $rule") if !@tests1;

    $self->{_test} .= sprintf(<<'__EVAL__',
if (
    %2$s
) {
    if ($self->{_states}{_rules}{'%1$s'} == 0) {
        $self->{_states}{_rules}{'%1$s'} = 1;
        if ($execute and my $func = $self->{_events}{_enter}{'%1$s'}) {
            ref($func) ? $func->(1) : $self->$func(1);
        }
    }
}
else {
    if ($self->{_states}{_rules}{'%1$s'} == 1) {
        $self->{_states}{_rules}{'%1$s'} = 0;
        if ($execute and my $func = $self->{_events}{_leave}{'%1$s'}) {
            ref($func) ? $func->(0) : $self->$func(0);
        }
    }
}
__EVAL__
        $self->_quote($rule),
        join("\n".'   and ', @tests1),
    );
}

sub _compile_test {
    my ($self) = @_;

    die("No tests") if !$self->{_test};

    my $test = sprintf(<<'__EVAL__',
sub {
    my ($self, $execute) = @_;

    $execute //= 1;

%1$s
};
__EVAL__
        $self->{_test},
    );

    print STDERR $test;
    $self->{_test} = eval $test;
    die($@) if ($@);
}

sub _states {
    my ($self) = @_;

    return
        sort(keys($self->{_states}{_counters})),
        sort(keys($self->{_states}{_flags})),
        sort(keys($self->{_states}{_enums})),
    ;
}

sub _type {
    my ($self, $name) = @_;

    return $self->{_types}{$name} if $self->{_types}{$name};
    die("Not a valid state: $name");
}

sub _change {
    my ($self, $state, $work) = @_;

    die("Negative changes are not allowed") if $state->{negate};
    die("Multiple changes are not allowed") if ref($state->{args});
    $work //= 1;

    my $name = $state->{name};
    my $args = $state->{args};

    if ($state->{type} eq 'counter') {
        my $value = $args // 1;
        $value *= -1 if !$work;
        die("Counter are not allowed to enter negative ranges")
            if $self->{_states}{_counter}{$name} + $value < 0;
        $self->{_states}{_counter}{$name} += $value;
    }
    elsif ($state->{type} eq 'flag') {
        my $value = $work ? 1 : 0;
        $self->{_states}{_flag}{$name} = $value;
    }
    elsif ($state->{type} eq 'enum') {
        my $value = $args // $self->{_enums}{$name}{default};

        die("Unknown value $value for $name")
            if !$self->{_enums}{$name}{types}{$value};

        $self->{_states}{_enum}{$name} = $value;
    }
    else {
        die("Type $state->{type} not allowed");
    }
}

sub _test {
    my ($self, $execute) = @_;

    $execute //= 1;

    $self->{_test}->($self, $execute);
}

sub _string2states {
    my ($self, $string) = @_;

    my %uniq;
    my @states;
    foreach my $state (split(/ /, $string || '')) {
        my ($name, @args) = split(/[:,]/, $state);
        my $negate = $name =~ s/^\-//;
        $name =~ s/^\+//;
        die("State $name not unique in $string") if $uniq{$name}++;

        push(
            @states,
            {
                name   => $name,
                negate => $negate,
                type   => $self->_type($name),
                args   => @args > 1 ? \@args : @args == 1 ? $args[0] : undef,
            },
        );

    }

    return @states;
}

=item $tran->work ($state)

This will increment all counter-states and enable all flag-states that are disabled. Enums are set to the submitted value.

=cut

sub work {
    my ($self, $string) = @_;

    $self->_change($_, 1) for $self->_string2states($string);
    $self->_test;
}

=item $tran->done ($state)

This will decrement all counter-states and disable all flag-states that are enabled. Enums are set to the submitted value.

=cut

sub done {
    my ($self, $string) = @_;

    $self->_change($_, 0) for $self->_string2states($string);
    $self->_test;
}

=item $tran->state ($state/$rule)

This will give you back the current value of a state/rule.

=cut

sub state {
    my ($self, $state) = @_;

    foreach my $type (qw/_counters _flags _enums _roles/) {
        return $self->{_states}{$type}{$state} if exists $self->{_states}{$type}{$state};
    }
    die("No such state/rule $state");
}

=back

=head1 SEE ALSO

=for :list
* L<State::Transition>;

=cut

1;

