#!/usr/bin/perl -w

use strict;
use Test::More tests => 4;
use_ok('Module::Packaged');

my $p = Module::Packaged->new();

my $dists = $p->check('Acme-Buffy');
is_deeply($dists, {cpan => '1.3'});

$dists = $p->check('Archive-Tar');
is_deeply($dists, {cpan => '1.07', gentoo => '1.03'});

$dists = $p->check('DBI');
is_deeply($dists, {cpan => '1.38', gentoo => '1.37'});
