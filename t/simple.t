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
  cpan    => '1.23',
  debian  => '1.23',
  fedora  => '1.08',
  freebsd => '1.23',
  gentoo  => '1.23',
  openbsd => '1.08',
  suse    => '1.08',
}, 'Archive-Tar');

$dists = $p->check('DBI');
is_deeply($dists, {
  cpan     => '1.47',
  debian   => '1.46',
  fedora   => '1.40',
  freebsd  => '1.47',
  gentoo   => '1.38',
  mandrake => '1.43',
  openbsd  => '1.43',
  suse     => '1.43',
}, 'DBI');


