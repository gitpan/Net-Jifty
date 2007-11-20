#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 13;
use lib 't/lib';
use Net::Jifty::Test;

my $j = Net::Jifty::Test->new();
$j->ua->clear();

my %args = (
    a => 'b',
    c => 'd',
);

$j->create("Foo", %args);
my ($name, $args) = $j->ua->next_call;
is($name, 'post', 'used post for create');
is_deeply($args->[1], 'http://jifty.org/=/model/JiftyApp.Model.Foo.yml', 'correct URL');
is_deeply($args->[2], \%args, 'correct arguments');

$j->ua->clear;
$j->read("Foo", a => 'b');
($name, $args) = $j->ua->next_call;
is($name, 'get', 'used get for read');
is_deeply($args->[1], 'http://jifty.org/=/model/JiftyApp.Model.Foo/a/b.yml', 'correct URL');

$j->ua->clear;
$j->update("Foo", a => 'b', c => 'C', d => 'e');
($name, $args) = $j->ua->next_call;
is($name, 'put', 'used put for update');
is_deeply($args->[1], 'http://jifty.org/=/model/JiftyApp.Model.Foo/a/b.yml', 'correct URL');
is_deeply($args->[2], {c => 'C', d => 'e'}, 'correct arguments');

$j->ua->clear;
$j->delete("Foo", '"' => '?');
($name, $args) = $j->ua->next_call;
is($name, 'delete', 'used delete for delete');
is_deeply($args->[1], 'http://jifty.org/=/model/JiftyApp.Model.Foo/%22/%3F.yml', 'correct URL');

$j->ua->clear;
$j->act("Foo", '"' => '?');
($name, $args) = $j->ua->next_call;
is($name, 'post', 'used post for act');
is_deeply($args->[1], 'http://jifty.org/=/action/JiftyApp.Action.Foo.yml', 'correct URL');
is_deeply($args->[2], {'"' => '?'}, 'correct arguments');

