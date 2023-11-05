#!/usr/bin/perl -w

# This script does everything required for XCode after building, including
# - re-linking dependency build areas back to build.local in each directory

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
    $path = "$path/../../../scripts";  # for esgit, in case we need it
    unshift @INC, $path;
}
use esgit;
use build;

# Make sure all output is in order
STDOUT->autoflush(1);
STDERR->autoflush(1);

# XCode runs from the same directory that the project bundle is in, which
# is the "ios" or "macos" directory inside the app (or lib) sandbox.

# This first part shouldn't have changed, but it doesn't hurt to check that the build process didn't screw up
my $pwd = cwd();
my ($name, $path) = fileparse $pwd;
$name =~ /^ios$|^macos$/i
  or die "This script is intended only for ios and macos, running at the same level as the project file bundle as the builds there do.\n";

# checkAndReturnAbsDependencies needs to be run at root of app module
chdir ".."
  or die "Couldn't cd to parent directory: $!\n";

my @absDependencies = checkAndReturnAbsDependencies;
