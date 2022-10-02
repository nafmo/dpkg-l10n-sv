# Copyright © 2008-2009 Raphaël Hertzog <hertzog@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

package Dpkg::Vendor;

use strict;
use warnings;
use feature qw(state);

our $VERSION = '1.01';
our @EXPORT_OK = qw(
    get_current_vendor
    get_vendor_info
    get_vendor_file
    get_vendor_dir
    get_vendor_object
    run_vendor_hook
);

use Exporter qw(import);
use List::Util qw(uniq);

use Dpkg ();
use Dpkg::ErrorHandling;
use Dpkg::Gettext;
use Dpkg::Build::Env;
use Dpkg::Control::HashCore;

my $origins = "$Dpkg::CONFDIR/origins";
$origins = $ENV{DPKG_ORIGINS_DIR} if $ENV{DPKG_ORIGINS_DIR};

=encoding utf8

=head1 NAME

Dpkg::Vendor - get access to some vendor specific information

=head1 DESCRIPTION

The files in $Dpkg::CONFDIR/origins/ can provide information about various
vendors who are providing Debian packages. Currently those files look like
this:

  Vendor: Debian
  Vendor-URL: https://www.debian.org/
  Bugs: debbugs://bugs.debian.org

If the vendor derives from another vendor, the file should document
the relationship by listing the base distribution in the Parent field:

  Parent: Debian

The file should be named according to the vendor name. The usual convention
is to name the vendor file using the vendor name in all lowercase, but some
variation is permitted. Namely, spaces are mapped to dashes ('-'), and the
file can have the same casing as the Vendor field, or it can be capitalized.

=head1 FUNCTIONS

=over 4

=item $dir = get_vendor_dir()

Returns the current dpkg origins directory name, where the vendor files
are stored.

=cut

sub get_vendor_dir {
    return $origins;
}

=item $fields = get_vendor_info($name)

Returns a Dpkg::Control object with the information parsed from the
corresponding vendor file in $Dpkg::CONFDIR/origins/. If $name is omitted,
it will use $Dpkg::CONFDIR/origins/default which is supposed to be a symlink
to the vendor of the currently installed operating system. Returns undef
if there's no file for the given vendor.

=cut

my $vendor_sep_regex = qr{[^A-Za-z0-9]+};

sub get_vendor_info(;$) {
    my $vendor = shift || 'default';
    my $vendor_key = lc $vendor =~ s{$vendor_sep_regex}{}gr;
    state %VENDOR_CACHE;
    return $VENDOR_CACHE{$vendor_key} if exists $VENDOR_CACHE{$vendor_key};

    my $file = get_vendor_file($vendor);
    return unless $file;
    my $fields = Dpkg::Control::HashCore->new();
    $fields->load($file, compression => 0) or error(g_('%s is empty'), $file);
    $VENDOR_CACHE{$vendor_key} = $fields;
    return $fields;
}

=item $name = get_vendor_file($name)

Check if there's a file for the given vendor and returns its
name.

The vendor filename will be derived from the vendor name, by replacing any
number of non-alphanumeric characters (that is B<[^A-Za-z0-9]>) into "B<->",
then lower-casing, as-is, lower-casing then capitalizing, and capitalizing.

In addition the above casing attempts will be tried also first as-is with
no replacements, and then by replacing only spaces to "B<->".

=cut

sub get_vendor_file(;$) {
    my $vendor = shift || 'default';

    my @names;
    my $vendor_sep = $vendor =~ s{$vendor_sep_regex}{-}gr;
    push @names, lc $vendor_sep, $vendor_sep, ucfirst lc $vendor_sep, ucfirst $vendor_sep;
    push @names, lc $vendor, $vendor, ucfirst lc $vendor, ucfirst $vendor;
    if ($vendor =~ s{\s+}{-}g) {
        push @names, lc $vendor, $vendor, ucfirst lc $vendor, ucfirst $vendor;
    }
    foreach my $name (uniq @names) {
        next unless -e "$origins/$name";
        return "$origins/$name";
    }
    return;
}

=item $name = get_current_vendor()

Returns the name of the current vendor. If DEB_VENDOR is set, it uses
that first, otherwise it falls back to parsing $Dpkg::CONFDIR/origins/default.
If that file doesn't exist, it returns undef.

=cut

sub get_current_vendor() {
    my $f;
    if (Dpkg::Build::Env::has('DEB_VENDOR')) {
        $f = get_vendor_info(Dpkg::Build::Env::get('DEB_VENDOR'));
        return $f->{'Vendor'} if defined $f;
    }
    $f = get_vendor_info();
    return $f->{'Vendor'} if defined $f;
    return;
}

=item $object = get_vendor_object($name)

Return the Dpkg::Vendor::* object of the corresponding vendor.
If $name is omitted, return the object of the current vendor.
If no vendor can be identified, then return the Dpkg::Vendor::Default
object.

The module name will be derived from the vendor name, by capitalizing,
lower-casing then capitalizing, as-is or lower-casing.

=cut

sub get_vendor_object {
    my $vendor = shift || get_current_vendor() || 'Default';
    my $vendor_key = lc $vendor =~ s{$vendor_sep_regex}{}gr;
    state %OBJECT_CACHE;
    return $OBJECT_CACHE{$vendor_key} if exists $OBJECT_CACHE{$vendor_key};

    my ($obj, @names);
    push @names, ucfirst $vendor, ucfirst lc $vendor, $vendor, lc $vendor;

    foreach my $name (uniq @names) {
        eval qq{
            pop \@INC if \$INC[-1] eq '.';
            require Dpkg::Vendor::$name;
            \$obj = Dpkg::Vendor::$name->new();
        };
        unless ($@) {
            $OBJECT_CACHE{$vendor_key} = $obj;
            return $obj;
        }
    }

    my $info = get_vendor_info($vendor);
    if (defined $info and defined $info->{'Parent'}) {
        return get_vendor_object($info->{'Parent'});
    } else {
        return get_vendor_object('Default');
    }
}

=item run_vendor_hook($hookid, @params)

Run a hook implemented by the current vendor object.

=cut

sub run_vendor_hook {
    my $vendor_obj = get_vendor_object();
    $vendor_obj->run_hook(@_);
}

=back

=head1 CHANGES

=head2 Version 1.01 (dpkg 1.17.0)

New function: get_vendor_dir().

=head2 Version 1.00 (dpkg 1.16.1)

Mark the module as public.

=head1 SEE ALSO

deb-origin(5).

=cut

1;
