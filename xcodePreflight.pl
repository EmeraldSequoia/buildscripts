#!/usr/bin/perl -w

# This script does everything required for XCode before building, including
# - verification of dependency links against deps.txt file
# - linking dependency build areas back to master

use strict;

# Strict checking
use strict;

# Standard Perl modules
use IO::Handle;
use Cwd;
use File::Basename;

# Set up to use local modules
BEGIN {
    use File::Basename;
    my ($name, $path) = fileparse $0;
    $path =~ s%/$%%o;
    unshift @INC, $path;
    $path = "$path/../../../scripts";  # for essvn, in case we need it
    unshift @INC, $path;
}
use esgit;
use build;

# Make sure all output is in order
STDOUT->autoflush(1);
STDERR->autoflush(1);

# XCode runs from the same directory that the project bundle is in, which
# is the "ios" or "macos" directory inside the app (or lib) sandbox.
#
# For dependency projects to work correctly in XCode, they must use the same
# build path.  We arrange this by linking all dependency modules' build directories
# back to the app build directory before we start.

my $pwd = cwd();
my ($name, $path) = fileparse $pwd;
$name =~ /^ios$|^macos$/i
  or die "This script is intended only for ios and macos, running at the same level as the project file bundle as the builds there do.\n";

chdir ".."
  or die "Couldn't cd to parent directory: $!\n";

my @absDependencies = checkAndReturnAbsDependencies;
