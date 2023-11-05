#!/usr/bin/perl -w

use strict;

use Cwd;
use Carp;

my $isDistributionBuild = 0;

# Only push the current branch
sub setupGitConfig {
    my $cmd = "git config --global push.default simple";
    warn ("$cmd\n");
    system($cmd) == 0
      or die "Couldn't set git config to push only current branch (see error above)\n";
}
setupGitConfig;

# Recursively checks the project and all of its dependencies are unmodified,
# and if so records, checks in, and pushes a file in the deps directory
# which in turn records the exact versions of each dependent library
# The version (after that checkin/push) of the given project is returned.
# If the method returns, all is well.
sub verifyProjectForDistribution {
    my $project = shift;
    my $saveWD = cwd();
    chdir $project
      or confess "Couldn't cd to $project from $saveWD: $!\n";
    open PIPE, "git status --short --branch |"
      or die "Couldn't open pipe to git st: $!\n";
    while (<PIPE>) {
        if (/^.?\?/) {
            confess "Distribution builds do not allow untracked files:\n$project/$_\n";
        } elsif (/\[ahead/) {
            confess "Distribution builds do not allow unpushed files:\n$project\n$_\n";
        } elsif (/.?M/) {
            confess "Distribution builds do not allow modified files:\n$project\n/$_\n";
        } elsif (/.?A/) {
            confess "Distribution builds do not allow added files not checked in:\n$project\n/$_\n";
        } elsif (/.?D/) {
            confess "Distribution builds do not allow deleted files not checked in:\n$project\n/$_\n";
        } elsif (/^#/) {
            # OK
        } else {
            confess "Distribution builds do not allow unexpected output from git status:\n$_\n";
        }
    }
    close PIPE;
    # So far so good
    if (-e "deps") {
        opendir DIR, "deps"
          or confess "Couldn't read directory deps from $project from $saveWD: $!\n";
        my @files = grep !/^\.|~$|^deps\.txt$|^distribution-versions\.txt$/, readdir DIR;
        closedir DIR;
        my @depsVersions;
        foreach my $file (@files) {
            if (-l "deps/$file") {
                push @depsVersions, [$file, verifyProjectForDistribution("deps/$file")];
            } else {
                warn "Odd: Unexpected non-link file $file found in deps in $project from $saveWD\n";
            }
        }
        my $depsVersionFile = "deps/distribution-versions.txt";
        if (-e "$depsVersionFile") {
            unlink "$depsVersionFile"
              or confess "Can't remove $depsVersionFile in $project from $saveWD: $!\n";
        }
        open DEPS, ">$depsVersionFile"
          or confess "Can't create $depsVersionFile in $project from $saveWD: !$\n";
        foreach my $depsVersion (@depsVersions) {
            my ($file, $version) = @$depsVersion;
            printf DEPS "%20s %s\n", $file, $version;
        }
        close DEPS;
        chomp(my $changeCount = `git status --short | wc -l`);
        if ($changeCount != 0) {
            my $cmd = "git commit -q -a -m 'Record current versions of dependent projects'";
            warn "$cmd\n";
            system($cmd);
            $cmd = "git push -q";
            warn "$cmd\n";
            system($cmd);
        }
        open PIPE, "git status --short --branch |"
          or confess "Couldn't open pipe: $!\n";
        while (<PIPE>) {
            if (/\[ahead/) {
                confess "git push appears to have failed:\n$_\n";
            }
            next if (/^##/);
            confess "git commit/push appears to have failed:\n$_\n";
        }
        close PIPE;
    }
    chomp(my $version = `git rev-parse HEAD`);
    #printf "Version for %s is returned as $version\n", cwd();
    chdir $saveWD
      or confess "Couldn't cd back to saved wd $saveWD: $!\n";
    return $version;
}

sub getVersion {
    my $configuration = $ENV{BUILD_STYLE};
    if ((!defined $configuration) || ($configuration eq "")) {
        $configuration = $ENV{CONFIGURATION};
    }
    my $version;
    if ($configuration =~ /distrib/i) {
        # warn "Checking for hacked strip wrapper...\n";
        # my $stripLocation = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/strip";
        # my $actualStripLocation = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/strip-actual";
        # if (!-e $stripLocation) {
        #     die "\nHmm.  Are you not running XCode from the Applications directory?\n";
        # }
        # if (!-e $actualStripLocation) {
        #     die "\nCannot build distribution version of this app without the hacked strip wrapper script\n\nTry runnning\n\n  sudo install-strip-wrapper.pl\n\n";
        # }
        # chomp(my $stripType = `file $stripLocation`);
        # $stripType =~ /perl.*script/
        #   or die "\nCannot build distribution version of this app without the hacked strip wrapper script\n\nTry runnning\n\n  sudo install-strip-wrapper.pl\n\n";
        # warn "...OK\n";
        $isDistributionBuild = 1;
        my $longVersion = verifyProjectForDistribution ".";
        $longVersion =~ /^(.......)/
          or confess "Unexpected version number return: $version\n";
        my $shortVersion = $1;
        $version = "g$shortVersion";
    } else {
        chomp(my $gitVersion = `git describe --match "r1"`);
        $gitVersion =~ /^r1-(\d+)-(g.......)$/
          or die "No git describe fails:  Is there no 'r1' tag in this git repository?\n";
        $version = $2;
        my $modified = "";
        open PIPE, "git status|"
          or die "Couldn't open pipe to git st: $!\n";
        while (<PIPE>) {
            if (/modified:|added:|deleted:/) {
                if ($modified !~ /M/) {
                    $modified .= "M";
                }
            } elsif (/is ahead of/) {
                $modified .= "L";
            }
        }
        close PIPE;
        $version .= $modified;
    }
    print "The $configuration version is ", $version, "\n";
    if ($isDistributionBuild) {
        # OK as is
    } elsif ($configuration =~ /debug/i) {
	$version .= " [Debug]";
    } elsif ($configuration =~ /release/i) {
	$version .= " [Release]";
    } else {
	$version .= " [?????]";
	die "Unexpected build style $configuration\n";
    }
    return $version;
}

sub findInfoPlist {
    opendir DIR, "."
      or die "Couldn't read working directory: $!\n";
    my @plists = grep /Info\.plist$/, readdir DIR;
    closedir DIR;

    if ((scalar @plists) == 0) {
        die sprintf "No *Info.plist file in working directory %s\n", cwd();
    }
    if ((scalar @plists) != 1) {
        die sprintf "More than one *Info.plist file in working directory %s\n", cwd();
    }
    return $plists[0];
}

sub filesAreIdentical {
    my ($file1, $file2) = @_;
    return system("cmp -s \"$file1\" \"$file2\"") == 0;
}

my @months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");

sub getDate {
    my (undef, undef, undef, $d, $m, $y) = localtime;
    return sprintf "%04d %s %02d", $y + 1900, $months[$m], $d;
}

defined $ENV{INFOPLIST_PATH} && defined $ENV{BUILT_PRODUCTS_DIR} && defined $ENV{SRCROOT}
  or die "Must run under XCode\n";

chdir $ENV{SRCROOT}
  or die "Couldn't cd to $ENV{SRCROOT}: $!\n";

my $version = getVersion;

my $appFlavor = shift;
my $emeraldProduct = "Emerald $appFlavor";

my $infoFile = findInfoPlist;

my $foundBundleVersion;
my $foundShortVersion;
open INFO, $infoFile
  or die "Couldn't read $infoFile: $!\n";
my $nextOneBundle = 0;
my $nextOneShort = 0;
while (<INFO>) {
    if (/>CFBundleVersion</) {
	$nextOneBundle = 1;
    } elsif ($nextOneBundle) {
	$foundBundleVersion = $1 if m/>([^<]+)</;
	$nextOneBundle = 0;
    } elsif (/>CFBundleShortVersionString/) {
        $nextOneShort = 1;
    } elsif ($nextOneShort) {
	$foundShortVersion = $1 if m/>([^<]+)</;
	$nextOneShort = 0;
    }
}
close INFO;

defined $foundBundleVersion
  or die "Couldn't find pattern in $infoFile\n";
if (not defined $foundShortVersion) {
    $foundShortVersion = $foundBundleVersion;
}

my $fullVersion = $foundShortVersion . "_$version ($foundBundleVersion)";

my $buildDate = localtime;
chomp(my $sandboxName = `pwd`);
my $debugInfo = "; Built $buildDate; $sandboxName";

my $versionLine = "$emeraldProduct Version $fullVersion";
my $fullVersionToken = $fullVersion;

if (!$isDistributionBuild) {
    $versionLine = "$emeraldProduct Version $fullVersion$debugInfo";
}

my $fileToMunge = "$ENV{BUILT_PRODUCTS_DIR}/$ENV{PRODUCT_NAME}.app/Help/Help.html";
if (!-e $fileToMunge) {
    $fileToMunge = "$ENV{BUILT_PRODUCTS_DIR}/$ENV{PRODUCT_NAME}.app/help.txt";
    if (!-e $fileToMunge) {
        die "Couldn't find a file to change\n";
    }
}

my $newFile = "$fileToMunge.new";
open F, $fileToMunge
    or die "Couldn't find $fileToMunge: $!\n";
open NEW, ">$newFile"
    or die "Couldn't write $newFile: $!\n";
while (<F>) {
    s/EMERALD_VERSION_STRING/$versionLine/g;
    print NEW $_;
}
close NEW;
close F;

if (filesAreIdentical $newFile, $fileToMunge) {
    unlink $newFile;
    print "No change in $fileToMunge\n";
    exit;
}

unlink $fileToMunge;
rename $newFile, $fileToMunge
  or die "Couldn't rename $newFile to $fileToMunge: $!\n";

print "Updated $fileToMunge with version information\n";
