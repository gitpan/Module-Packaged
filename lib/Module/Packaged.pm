package Module::Packaged;
use strict;
use CPAN::DistnameInfo;
use Cache::FileCache;
use IO::File;
use IO::Zlib;
use File::Slurp;
use File::Spec::Functions qw(catdir catfile tmpdir);
use LWP::Simple qw(mirror);
use Parse::Debian::Packages;
use Sort::Versions;
use vars qw($VERSION);
$VERSION = '0.67';

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  # At some point I should unify these caching schemes, but for now
  # let's be ultra nice to the websites
  my $dir = tmpdir();
  $dir = catdir($dir, "mod_pac");
  mkdir $dir || die "Failed to mkdir $dir";
  chmod 0777, $dir || die "Failed to chmod $dir";
  $self->{DIR} = $dir;

  # The data takes a while to parse, so let's cache it
  my $cache = Cache::FileCache->new({
    'namespace'          => 'module_packaged',
    'default_expires_in' => '1 hour',
    'cache_depth'        => 1,
  });

  my $data = $cache->get('data');
  if (defined $data) {
    # It's cached, excellent
    $self->{data} = $data;
  } else {
    # Not cached, generate it
    $self->fetch_cpan;
    $self->fetch_debian;
    $self->fetch_freebsd;
    $self->fetch_gentoo;
    $self->fetch_openbsd;
    $cache->set('data', $self->{data});
  }

  return $self;
}

sub cache {
  my $self = shift;
  return $self->{cache};
}

sub mirror_file {
  my $self = shift;
  my $url  = shift;
  my $file = shift;
  my $dir  = $self->{DIR};

  my $filename = catfile($dir, $file);
  mirror($url, $filename);
  chmod 0666, $filename || die "Failed to chmod $filename";

  return $filename;
}

sub fetch_cpan {
  my $self = shift;
  my $filename = $self->mirror_file(
      "http://cpan.geekflat.org/modules/02packages.details.txt.gz",
      "02packages.gz" );

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

  my $filename = $self->mirror_file(
      "http://www.gentoo.org/dyn/pkgs/dev-perl/index.xml",
      "gentoo.html");

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

sub fetch_freebsd {
  my $self = shift;
  my $filename = $self->mirror_file( "http://www.freebsd.org/ports/perl5.html",
                                     "freebsd.html" );
  my $file = read_file($filename) || die "Error opening file $filename!";

  for my $package ($file =~ m/a id="p5-(.*?)"/g) {
    my ($dist, $version) = $package =~ /^(.*?)-(\d.*)$/ or next;
    # tidy up the oddness that is p5-DBI-137-1.37
    $version =~ s/^\d+-//;

    # only populate if CPAN already has
    $self->{data}{$dist}{freebsd} = $version
      if $self->{data}{$dist};
  }
}

sub fetch_debian {
    my $self = shift;

    my %dists = map { lc $_ => $_ } keys %{ $self->{data} };
    for my $dist (qw( stable testing unstable )) {
        my $filename = $self->mirror_file(
            "http://ftp.debian.org/dists/$dist/main/binary-i386/Packages.gz",
            "debian-$dist-Packages.gz" );

        my $fh = IO::Zlib->new;
        die "Error opening file $filename!" unless $fh->open($filename, "rb");

        my $debthing = Parse::Debian::Packages->new( $fh );
        while (my %package = $debthing->next) {
            next unless $package{Package} =~ /lib(.*?)-perl$/;
            my $dist = $dists{ $1 } or next;
            # don't care about the debian version
            my ($version) = $package{Version} =~ /^(.*?)-/;

            $self->{data}{$dist}{debian} = $version
              if $self->{data}{$dist};
        }
    }
}

sub fetch_openbsd {
  my $self = shift;
  my $filename = $self->mirror_file(
      "http://www.openbsd.org/3.2_packages/i386.html",
      "openbsd.html" );
  my $file = read_file($filename) || die "Error opening file $filename!";

  for my $package ($file =~ m/href=i386\/p5-(.*?)\.tgz-long/g) {
    my ($dist, $version) = $package =~ /^(.*?)-(\d.*)$/ or next;

    # only populate if CPAN already has
    $self->{data}{$dist}{openbsd} = $version
      if $self->{data}{$dist};
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
  # $dists is now:
  # {
  # cpan    => '1.07',
  # debian  => '1.03',
  # freebsd => '1.07',
  # gentoo  => '1.03',
  # openbsd => '0.22',
  # }
  # meaning that Archive-Tar is at version 1.07 on CPAN and FreeBSD
  # but only version 1.03 on Debian Gentoo and 0.22 on OpenBSD

=head1 DESCRIPTION

CPAN consists of distributions. However, CPAN is not an isolated
system - distributions are also packaged in other places, such as for
operating systems. This module reports whether CPAN distributions are
packaged for various operating systems, and which version they have.

Note: only CPAN, Debian, FreeBSD, Gentoo, and OpenBSD are currently
supported. I want to support versions of PPM, and Redhat. Patches are
welcome.

=head1 COPYRIGHT

Copyright (c) 2003 Leon Brocard. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

Leon Brocard, leon@astray.com

