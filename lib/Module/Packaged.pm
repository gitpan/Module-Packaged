package Module::Packaged;
use strict;
use IO::File;
use IO::Zlib;
use File::Spec::Functions qw(catdir catfile tmpdir);
use LWP::Simple qw(mirror);
use Parse::CPAN::Packages;
use Parse::Debian::Packages;
use Sort::Versions;
use Storable qw(store retrieve);
use vars qw($VERSION);
$VERSION = '0.77';

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $dir = tmpdir();
  $dir = catdir($dir, "mod_pac");
  mkdir $dir || die "Failed to mkdir $dir";
  chmod 0777, $dir || die "Failed to chmod $dir";
  $self->{DIR} = $dir;

  my $t = (stat "$dir/stored")[9];

  if (defined $t && (time - $t) < 3600) {
    # It's cached, excellent
    my $data = retrieve("$dir/stored") || die "Error reading: $!";
    $self->{data} = $data;
  } else {
    # Not cached, generate it
    $self->_fetch_cpan;
    $self->_fetch_debian;
    $self->_fetch_fedora;
    $self->_fetch_freebsd;
    $self->_fetch_gentoo;
    $self->_fetch_mandrake;
    $self->_fetch_openbsd;
    $self->_fetch_suse;
    store($self->{data}, "$dir/stored") || die "Error storing: $!";
  }

  return $self;
}

sub _mirror_file {
  my $self = shift;
  my $url  = shift;
  my $file = shift;
  my $dir  = $self->{DIR};

  my $filename = catfile($dir, $file);
  mirror($url, $filename);
  chmod 0666, $filename || die "Failed to chmod $filename";

  return $filename;
}

sub _fetch_cpan {
  my $self = shift;
  my $filename = $self->_mirror_file(
      "http://cpan.geekflat.org/modules/02packages.details.txt.gz",
      "02packages.gz" );

  my $fh = IO::Zlib->new;
  die "Error opening file $filename!" unless $fh->open($filename, "rb");
  my $details = join '', <$fh>;
  $fh->close;

  my $p = Parse::CPAN::Packages->new($details);

  foreach my $dist ($p->latest_distributions) {
    $self->{data}->{$dist->dist}->{cpan} = $dist->version;
  }
}

sub _fetch_gentoo {
  my $self = shift;

  my $filename = $self->_mirror_file(
      "http://www.gentoo.org/dyn/gentoo_pkglist_x86.txt",
      "gentoo.html");

  my $file = $self->_slurp($filename);
  $file =~ s{</a></td>\n}{</a></td>}g;

  my @dists = keys %{$self->{data}};

  foreach my $line (split "\n", $file) {
    next unless ($line =~ m/dev-perl/);
    my $dist;
    $line =~ s/\.ebuild//g; 
    my ($package, $version, $trash) = split(' ', $line);
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

sub _fetch_fedora {
  my $self = shift;
  my $filename = $self->_mirror_file( "http://fedora.redhat.com/projects/package-list/", "fedora.html" );
  my $file = $self->_slurp($filename);

  foreach my $line (split "\n", $file) {
    next unless $line =~ /^perl-/;
    my($dist, $version) = $line =~ m{perl-(.*?)</td><td class="column-2">(.*?)</td>};

    # only populate if CPAN already has
    $self->{data}{$dist}{fedora} = $version
      if $self->{data}{$dist};
  }
}

sub _fetch_suse {
  my $self = shift;
  my $filename = $self->_mirror_file( "http://www.suse.de/us/private/products/suse_linux/i386/packages_professional/index_all.html", "suse.html" );
  my $file = $self->_slurp($filename);

  foreach my $line (split "\n", $file) {
    my($dist, $version) = $line =~ m{">perl-(.*?) (.*?) </a>};
    next unless $dist;

    # only populate if CPAN already has
    $self->{data}{$dist}{suse} = $version
      if $self->{data}{$dist};
  }
}

sub _fetch_mandrake {
  my $self = shift;
  my $filename = $self->_mirror_file("http://www.mandrakelinux.com/en/10.0/features/15.php3", "mandrake.html" );
  my $file = $self->_slurp($filename);

  foreach my $line (split "\n", $file) {
    next unless $line =~ /^perl-/;
    my($dist, $version) = $line =~ m{perl-(.*?)-(.*?)-\d+mdk};
    next unless $dist;

    # only populate if CPAN already has
    $self->{data}{$dist}{mandrake} = $version
      if $self->{data}{$dist};
  }
}
sub _fetch_freebsd {
  my $self = shift;
  my $filename = $self->_mirror_file( "http://www.freebsd.org/ports/perl5.html",
                                     "freebsd.html" );
  my $file = $self->_slurp($filename);

  for my $package ($file =~ m/a id="p5-(.*?)"/g) {
    my ($dist, $version) = $package =~ /^(.*?)-(\d.*)$/ or next;
    # tidy up the oddness that is p5-DBI-137-1.37
    $version =~ s/^\d+-//;

    # only populate if CPAN already has
    $self->{data}{$dist}{freebsd} = $version
      if $self->{data}{$dist};
  }
}

sub _fetch_debian {
    my $self = shift;

    my %dists = map { lc $_ => $_ } keys %{ $self->{data} };
    for my $dist (qw( stable testing unstable )) {
        my $filename = $self->_mirror_file(
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

sub _fetch_openbsd {
  my $self = shift;
  my $filename = $self->_mirror_file(
      "http://www.openbsd.org/3.4_packages/i386.html",
      "openbsd.html" );
  my $file = $self->_slurp($filename);

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

sub _slurp {
  my($self, $filename) = @_;
  open(IN, $filename) || die "Module::Packaged: Error opening file $filename!";
  my $content = join '', <IN>;
  close IN;
  return $content;
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
  # cpan    => '1.08',
  # debian  => '1.03',
  # fedora  => '0.22',
  # freebsd => '1.07',
  # gentoo  => '1.05',
  # openbsd => '0.22',
  # suse    => '0.23',
  # }

  # meaning that Archive-Tar is at version 1.08 on CPAN but only at
  # version 1.07 on FreeBSD, version 1.05 on Gentoo, version 1.03 on
  # Debian, version 0.23 on SUSE and version 0.22 on OpenBSD

=head1 DESCRIPTION

CPAN consists of distributions. However, CPAN is not an isolated
system - distributions are also packaged in other places, such as for
operating systems. This module reports whether CPAN distributions are
packaged for various operating systems, and which version they have.

Note: only CPAN, Debian, Fedora, FreeBSD, Gentoo, Mandrake, OpenBSD
and SUSE are currently supported. I want to support everything
else. Patches are welcome.

=head1 METHODS

=head2 new()

The new() method is a constructor:

  my $p = Module::Packaged->new();

=head2 check()

The check() method returns a hash reference. The keys are various
distributions, the values the version number included:

  my $dists = $p->check('Archive-Tar');

=head1 COPYRIGHT

Copyright (c) 2003-4 Leon Brocard. All rights reserved. This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

Leon Brocard, leon@astray.com

