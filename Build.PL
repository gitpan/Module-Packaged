use strict;
use Module::Build;

my $build = Module::Build->new(
  create_makefile_pl => 'traditional',
  license     => 'perl',
  module_name => 'Module::Packaged',
  requires    => {
    'Cache::Cache'        => '1.02',
    'IO::File'            => '1.08',
    'IO::Zlib'            => '1.01',
    'LWP::Simple'         => '1.38',
    'Sort::Versions'      => '1.50',
    'Test::More'          => '0.47',
    'Parse::CPAN::Packages' => '2.20',
    'Parse::Debian::Packages' => '0.01',
  },
);
$build->create_build_script;
