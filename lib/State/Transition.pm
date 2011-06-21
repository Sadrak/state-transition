
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

=item 'enum:on,off,auto' => ...

Enumeration, the first is the default.

=item 'counter:12 -flag -enum:auto' => ...

State will be active when counter == 12, flag is off and enum is not auto.

=item '' => ...

This rule is a special case, it means the initial state is set. You can change the initial.

=back

=item counters => '...'

Counters are simple positive integers as a state. At a rule you can use them without argument, that means 0 = off and >0 = on or with a integer (counter:12) or with a range (counter1:4..8) or a combination of all those (counter:12,4..8).

=item flags   => '...'

Flags are only on/off states. You can multiple times work on that state and a
single done will finish that. Another finish will do nothing at all.

=item enums   => '...'

Enums are multivalue flags. A call to done() will do the same then a call to
work(). You always have to submit the new value like 'enum:off'.

=item initial => '...'

Here you can define the initial state of the object. Defaults to an empty string (''), that means every defined counter is 0, every defined flag is off and every defined enum is at default.

=back

=cut

sub new {
}

=item $tran->work ($state)

This will increment all counter-states and enable all flag-states that are disabled. Enums are set to the submitted value.

=cut

sub work {
}

=item $tran->done ($state)

This will decrement all counter-states and disable all flag-states that are enabled. Enums are set to the submitted value.

=cut

sub done {
}

=back

=head1 SEE ALSO

=for :list
* L<State::Transition>;

=cut

1;

