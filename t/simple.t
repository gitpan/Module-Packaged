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
  cpan    => '1.10',
  debian  => '1.08',
  fedora  => '1.08',
  freebsd => '1.08_1',
  gentoo  => '1.09',
  openbsd => '1.03',
  suse    => '1.08',
}, 'Archive-Tar');

$dists = $p->check('DBI');
is_deeply($dists, {
  cpan     => '1.43',
  debian   => '1.43',
  fedora   => '1.40',
  freebsd  => '1.37',
  gentoo   => '1.38',
  mandrake => '1.40',
  openbsd  => '1.37',
  suse     => '1.41',
}, 'DBI');
