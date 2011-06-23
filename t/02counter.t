use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Differences;

no warnings 'qw';

use_ok('State::Transition', 'loaded ok');

my $dynamic_rules = sub {
    my $states = shift;
    my %rules;

    foreach my $rule (@_) {
        $rules{$rule} = {
            enter => sub { $states->{$rule}++; },
            leave => sub { $states->{$rule}--; },
        };
    } 

    return \%rules;
};

subtest 'one counter, positive rules', sub {
    my %current;
    my $term = new_ok('State::Transition', [
        counters => 'counter1',
        rules    => $dynamic_rules->(
            \%current,
            qw/
            counter1
            counter1:2
            counter1:4..5
            counter1:4..6,8
            counter1:10..*
            counter1:0
            /,
        ),
    ], '->new successfull');
    $current{'counter1:0'} = 1;
    my %expected = %current;

    throws_ok(
        sub { $term->done('counter1'); },
        qr/Counter are not allowed to enter negative ranges/,
        'no negative counters',
    );

    $term->work('counter1');
    $expected{'counter1'} = 1;
    $expected{'counter1:0'} = 0;
    eq_or_diff(\%current, \%expected, 'rule1 entered, rule6 leaved');

    $term->work('counter1');
    $expected{'counter1:2'} = 1;
    eq_or_diff(\%current, \%expected, 'rule2 entered');

    $term->work('counter1');
    $expected{'counter1:2'} = 0;
    eq_or_diff(\%current, \%expected, 'rule2 leaved');

    $term->done('counter1');
    $expected{'counter1:2'} = 1;
    eq_or_diff(\%current, \%expected, 'rule2 entered');

    $term->work('counter1:3');
    $expected{'counter1:2'} = 0;
    $expected{'counter1:4..5'} = 1;
    $expected{'counter1:4..6,8'} = 1;
    eq_or_diff(\%current, \%expected, 'rule2 leaved, rule3 entered, rule4 entered');

    $term->done('counter1');
    eq_or_diff(\%current, \%expected, 'no changes');

    $term->work('counter1:4');
    $expected{'counter1:4..5'} = 0;
    eq_or_diff(\%current, \%expected, 'rule3 leaved');

    $term->work('counter1');
    $expected{'counter1:4..6,8'} = 0;
    eq_or_diff(\%current, \%expected, 'rule4 leaved');

    $term->work('counter1');
    $expected{'counter1:10..*'} = 1;
    eq_or_diff(\%current, \%expected, 'rule5 entered');

    $term->done('counter1:10');
    $expected{'counter1'} = 0;
    $expected{'counter1:10..*'} = 0;
    $expected{'counter1:0'} = 1;
    eq_or_diff(\%current, \%expected, 'rule1 leaved, rule5 leaved, rule6 entered');
};

subtest 'one counter, negative rules', sub {
    my %current;
    my $term = new_ok('State::Transition', [
        counters => 'counter1',
        rules    => $dynamic_rules->(
            \%current,
            qw/
            -counter1
            -counter1:2
            -counter1:4..5
            -counter1:4..6,8
            -counter1:10..*
            -counter1:0
            /,
        ),
    ], '->new successfull');
    $current{'-counter1'} = 1;
    $current{'-counter1:2'} = 1;
    $current{'-counter1:4..5'} = 1;
    $current{'-counter1:4..6,8'} = 1;
    $current{'-counter1:10..*'} = 1;
    my %expected = %current;

    $term->work('counter1');
    $expected{'-counter1'} = 0;
    $expected{'-counter1:0'} = 1;
    eq_or_diff(\%current, \%expected, 'rule1 leaved, rule6 entered');

    $term->work('counter1');
    $expected{'-counter1:2'} = 0;
    eq_or_diff(\%current, \%expected, 'rule2 leaved');

    $term->work('counter1');
    $expected{'-counter1:2'} = 1;
    eq_or_diff(\%current, \%expected, 'rule2 entered');

    $term->work('counter1');
    $expected{'-counter1:4..5'} = 0;
    $expected{'-counter1:4..6,8'} = 0;
    eq_or_diff(\%current, \%expected, 'rule3 leaved, rule4 leaved');

    $term->work('counter1:6');
    $expected{'-counter1:4..5'} = 1;
    $expected{'-counter1:4..6,8'} = 1;
    $expected{'-counter1:10..*'} = 0;
    eq_or_diff(\%current, \%expected, 'rule3 entered, rule4 entered, rule 5 leaved');

    $term->done('counter1:10');
    $current{'-counter1'} = 1;
    $current{'-counter1:2'} = 1;
    $current{'-counter1:10..*'} = 1;
    $current{'-counter1:0'} = 0;
    eq_or_diff(\%current, \%expected, 'rule1 entered, rule2 entered, rule 5 entered, rule6 leaved');
};


done_testing();

