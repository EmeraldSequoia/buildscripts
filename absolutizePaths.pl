#!/usr/bin/perl -w

use strict;

use Cwd;
use File::Basename;

# This filter script, used to process compiler output for emacs, takes partial pathnames
# which may contain links and replaces them with absolute pathnames.

my $saveWD = cwd();

sub absolutizePath {
    my $path = shift;
    my ($name, $dir) = fileparse $path;
    if (chdir $dir) {
        my $wd = cwd();
        chdir $saveWD
          or die "Couldn't return to original path";
        return $wd . "/$name";
    } else {
        # print "... can't cd to $dir: $!\n";
        # No can do; just return original
        return $path;
    }
}

while (<>) {
    #print "\nInput: $_";
    my $pat = "[-a-zA-Z0-9_\\./]*\\.\\.\/[-a-zA-Z0-9_\\./]+";
    while (m%$pat%) {
        my $path = $&;
        #print "Path found: '$path'\n";
        my $newPath = absolutizePath $path;
        if ($newPath eq $path) {
            last;  # Couldn't change anything, so skipping
        }
        #print "... replacing with: '$newPath'\n";
        s%$pat%$newPath%;
    }
    print " ";
    print;
}
