#!/usr/bin/perl -w

use strict;
use Test::More tests => 4;
use_ok('Module::Packaged');

warn "\n# These tests take a while to run as we need to mirror large\n";
warn "# files from the web and then parse them. Please be patient.\n";

my $p = Module::Packaged->new();

my $dists = $p->check('Acme-Buffy');
is_deeply($dists, {
  cpan => '1.3',
}, 'Acme-Buffy');

$dists = $p->check('Archive-Tar');
is_deeply($dists, {
  cpan    => '1.08',
  debian  => '1.08',
  freebsd => '1.08',
#  gentoo  => '1.03',
  openbsd => '1.03',
}, 'Archive-Tar');

$dists = $p->check('DBI');
is_deeply($dists, {
  cpan    => '1.41',
  debian  => '1.41',
  freebsd => '1.37',
#  gentoo  => '1.37',
  openbsd => '1.37',
}, 'DBI');
