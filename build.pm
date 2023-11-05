package build;

# Strict checking
use strict;

# Standard modules
use File::Path;
use IO::Handle;
use Cwd;
use Carp;

# Make sure all output is in order
STDOUT->autoflush(1);
STDERR->autoflush(1);

# Exported symbols
require Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw(checkAndReturnAbsDependencies);

# Run this from the root of the module sandbox
sub checkAndReturnAbsDependencies {
    my $moduleRoot = cwd();
    my $depsDir = "$moduleRoot/deps";
    my $depsFile = "$depsDir/deps.txt";

    my %deps;

    if (-e $depsFile) {
        open DEPS, $depsFile
          or die "Couldn't read $depsFile: $!\n";
        while (<DEPS>) {
            chomp;
            s/\#.*$//go;        # Remove comments
            next if (/^\s*$/);  # Skip empty lines
            m%^\s*(\S+)/(\S+)\s+(\S+)\s*$%
              or die "Unexpected line in $depsFile :$!\n";
            my $kind = $1;
            my $module = $2;
            my $trunkBranchOrTag = $3;
            $deps{$module} = [$kind, $trunkBranchOrTag];
        }
        close DEPS;
    }

    opendir DEPSDIR, $depsDir
      or die "Couldn't read directory $depsDir: $!\n";
    my @entries = grep !/^\.|^deps\.txt/i, readdir DEPSDIR;
    closedir DEPSDIR;

    my @verifiedAbsDependencies;

    foreach my $entry (@entries) {
        my $path = "$depsDir/$entry";
        if (-l $path) {
            my $dependency = readlink $path;
            $dependency =~ m%/([^/]+)/([^/]+)/([^/]+)/?$%
              or die "Unexpected link format in $path\n";
            my $kind = $1;
            my $module = $2;
            my $sandbox = $3;
            my $descriptor = $deps{$module};
            defined $descriptor
              or die "The link $path pointing at module $module has no corresponding entry in $depsFile\n";
            $deps{$module} = undef;    # Remove hash entry so we can detect missing links later
            my ($declaredKind, $declaredTrunkBranchOrTag) = @$descriptor;
            $declaredKind eq $kind
              or die "The link $path has a module kind '$kind' that doesn't match the kind '$declaredKind' declared in $depsFile\n";
            $dependency !~ m%^/%
              or die "The link $path has an absolute path -- use a relative path here\n";
            my $dependencyPath = "$depsDir/$dependency";
            -e $dependencyPath
              or die "The link $path points at a nonexistent directory\n";
            -d $dependencyPath
              or die "The link $path points at something that isn't a directory\n";
            my $saveWD = cwd();
            chdir $dependencyPath
              or die "Couldn't cd to $path: $!\n";
            my $absPath = cwd();
            $absPath =~ m%/([^/]+)/([^/]+)/([^/]+)/?$%
              or die "The path linked to by $path ($absPath) doesn't match the link $dependency\n";
            my $absKind = $1;
            my $absModule = $2;
            my $absSandbox = $3;
            ($absKind eq $kind) && ($absModule eq $module) && ($absSandbox eq $sandbox)
              or die "The path linked to by $path ($absPath) doesn't match the link $dependency\n";
            if (!-d ".git" && !-d "../.git" && !-d "../../.git" && !-d "../../../.git" && !-d "../../../../.git" && !-d "../../../../../.git" && !-d "../../../../../../.git" ) {
                die "Error: $path links to a directory which is not git-controlled.\n";
            }
            chomp(my $infoLine = `git config remote.origin.url`);
            $infoLine =~ m%^.*/([^/]+)/([^/]+)\.git$%
              or die "Unexpected output from git config remote.origin.url in $absPath: '$infoLine'\n";
            my $infoKind = $1;
            my $infoModule = $2;
            $infoKind eq $kind
              or die "The path linked to by $path ($absPath) has a module kind of '$infoKind' in svn instead of the expected '$kind'\n";
            $infoModule eq $module
              or die "The path linked to by $path ($absPath) has a module of '$infoModule' in svn instead of the expected '$module'\n";
            chomp($infoLine = `git branch | grep '^*'`);
            $infoLine =~ m%^\* (.+)$%
              or die "Unexpected output from git branch in $absPath: '$infoLine'\n";
            my $infoTrunkBranchOrTag = $1;
            $infoTrunkBranchOrTag = $declaredTrunkBranchOrTag
              or die "The path linked to by $path ($absPath) has a trunk, branch, or tag spec of '$infoTrunkBranchOrTag' in svn instead of the expected '$declaredTrunkBranchOrTag'\n";
            push @verifiedAbsDependencies, $absPath;
            chdir $saveWD
              or die "Couldn't cd back to $saveWD: !$\n";
        } elsif ($entry eq "android-modules") {
            warn "Need checking for android-modules...\n";
        } else {
            die "An entry in the deps directory is not a link: $path\n";
        }
    }
    for (my ($key, $value) = each %deps) {
        if (defined $value) {
            die "Did not find link for $key declared in depsFile $depsFile in $depsDir\n";
        }
    }

    return @verifiedAbsDependencies;
}

1;
