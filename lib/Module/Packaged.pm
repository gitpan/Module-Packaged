package Module::Packaged;
use strict;
use CPAN::DistnameInfo;
use IO::File;
use IO::Zlib;
use File::Slurp;
use File::Spec::Functions qw(catdir catfile tmpdir);
use LWP::Simple qw(mirror);
use Sort::Versions;
use vars qw($VERSION);
$VERSION = '0.34';

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $dir = tmpdir();
  $dir = catdir($dir, "mod_pac");
  mkdir $dir || die "Failed to mkdir $dir";
  chmod 0777, $dir || die "Failed to chmod $dir";
  $self->{DIR} = $dir;

  $self->fetch_cpan;
  $self->fetch_gentoo;

  return $self;
}

sub fetch_cpan {
  my $self = shift;
  my $dir  = $self->{DIR};

  my $url = "http://cpan.geekflat.org/modules/02packages.details.txt.gz";
  my $filename = catfile($dir, "02packages.gz");
  mirror($url, $filename);
  chmod 0666, $filename || die "Failed to chmod $filename";

  my $fh = IO::Zlib->new;
  die "Error opening file $filename!" unless $fh->open($filename, "rb");

  # Skip the prologue
  1 while <$fh> ne "\n";

  while (my $line = <$fh>) {
    chomp $line;
    my($module, $version, $prefix) = split / +/, $line;
    my $d = CPAN::DistnameInfo->new($prefix);
    my $dist = $d->dist;
    next unless $dist;
    # We want the highest version
    my $new = $d->version || '0';
    my $old = $self->{data}->{$dist}->{cpan} || '0';
    my $high = (sort { versioncmp($a, $b) } $new, $old)[1];
    $self->{data}->{$dist}->{cpan} = $high;
  }

  $fh->close;
}

sub fetch_gentoo {
  my $self = shift;
  my $dir  = $self->{DIR};

  my $url = "http://www.gentoo.org/dyn/pkgs/dev-perl/index.xml";
  my $filename = catfile($dir, "gentoo.html");
  mirror($url, $filename);
  chmod 0666, $filename || die "Failed to chmod $filename";

  my $file = read_file($filename) || die "Error opening file $filename!";
  $file =~ s{</a></td>\n}{</a></td>}g;

  my @dists = keys %{$self->{data}};

  foreach my $line (split "\n", $file) {
    my $dist;
    my ($package, $version) = $line =~ m{">([^<]+?)</a>.+">([^<]+?)</td>};
    next unless $package;

    # Let's try to find a cpan dist that matches the package name
    if (exists $self->{data}->{$package}) {
      $dist = $package;
    } else {
      foreach my $d (@dists) {
	if (lc $d eq lc $package) {
	  $dist = $d;
	  last;
	}
      }
    }

    if ($dist) {
      $self->{data}->{$dist}->{gentoo} = $version;
    } else {
      # I should probably care about these and fix them
      # warn "Could not find $package: $version\n";
    }
  }
}

sub check {
  my($self, $dist) = @_;

  return $self->{data}->{$dist};
}

1;

__END__

=head1 NAME

Module::Packaged - Report upon packages of CPAN distributions

=head1 SYNOPSIS

  use Module::Packages;

  my $p = Module::Packaged->new();
  my $dists = $p->check('Archive-Tar');
  # $dists is now {cpan => '1.07', gentoo => '1.03'}
  # meaning that Archive-Tar is at version 1.07 on CPAN
  # but only version 1.03 on Gentoo

=head1 DESCRIPTION

CPAN consists of distributions. However, CPAN is not an isolated
system - distributions are also packaged in other places, such as for
operating systems. This module reports whether CPAN distributions are
packaged for various operating systems, and which version they have.

Note: only CPAN and Gentoo are currently supported. I want to support
versions of Debian, FreeBSD, OpenBSD, PPM, and Redhat. Patches are
welcome.

=head1 COPYRIGHT

Copyright (c) 2003 Leon Brocard. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

Leon Brocard, leon@astray.com

