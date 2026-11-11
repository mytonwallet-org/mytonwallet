#!/usr/bin/env bash

set -euo pipefail

exec /usr/bin/perl -e '
use strict;
use warnings;
use Errno qw(EAGAIN EINTR EWOULDBLOCK);
use Fcntl qw(LOCK_EX LOCK_NB);
use File::Path qw(make_path);
use POSIX qw(SIG_BLOCK SIG_SETMASK SIGHUP SIGINT SIGTERM sigprocmask);
use JSON::PP;
use Time::HiRes qw(sleep stat);

if (grep { $_ eq "-derivedDataPath" } @ARGV) {
    die "Do not pass -derivedDataPath; use --slot 1, 2 or 3 instead.\n";
}

my (@filters, $result_bundle, $runs_tests, $enumerates);
for (my $i = 0; $i < @ARGV; $i++) {
    if ($ARGV[$i] eq "test" || $ARGV[$i] eq "test-without-building") {
        $runs_tests = 1;
    } elsif ($ARGV[$i] eq "-enumerate-tests") {
        $enumerates = 1;
    } elsif ($ARGV[$i] =~ /\A-only-testing:(.+)\z/) {
        push @filters, $1;
    } elsif ($ARGV[$i] eq "-only-testing" && $i + 1 < @ARGV) {
        push @filters, $ARGV[++$i];
    } elsif ($ARGV[$i] eq "-resultBundlePath" && $i + 1 < @ARGV) {
        $result_bundle = $ARGV[++$i];
    }
}

my $requested_slot;
if (@ARGV && $ARGV[0] eq "--slot") {
    shift @ARGV;
    $requested_slot = shift @ARGV;
    die "Usage: dev/iosXcodebuild.sh [--slot 1|2|3] <xcodebuild arguments>\n"
        unless defined($requested_slot) && $requested_slot =~ /\A[123]\z/;
}

my $root = $ENV{MTW_DERIVED_DATA_ROOT};
$root = "$ENV{HOME}/Library/Developer/Xcode/DerivedData" unless defined($root) && length($root);
make_path($root);

my $checkout = qx(git rev-parse --show-toplevel 2>/dev/null);
if ($? == 0) {
    chomp $checkout;
} else {
    $checkout = $ENV{PWD};
}

my $selected;
my $has_waited = 0;
while (!$selected) {
    my @available;
    for my $number (defined($requested_slot) ? ($requested_slot) : (1 .. 3)) {
        my $path = "$root/MyTonWallet-slot-$number";
        open my $lock, ">>", "$path.lock" or die "Cannot open $path.lock: $!\n";
        unless (flock($lock, LOCK_EX | LOCK_NB)) {
            next if $! == EWOULDBLOCK || $! == EAGAIN;
            die "Cannot lock $path.lock: $!\n";
        }

        my $last_checkout = "";
        my $used_at = 0;
        my $priority = 1;
        if (-e "$path.checkout") {
            open my $metadata, "<", "$path.checkout" or die "Cannot read $path.checkout: $!\n";
            $last_checkout = do { local $/; <$metadata> } // "";
            $used_at = (stat($metadata))[9];
            $priority = $last_checkout eq $checkout ? 0 : 2;
        }
        push @available, { path => $path, lock => $lock, priority => $priority, used_at => $used_at, number => $number };
    }

    if (@available) {
        ($selected) = sort {
            $a->{priority} <=> $b->{priority}
                || $a->{used_at} <=> $b->{used_at}
                || $a->{number} <=> $b->{number}
        } @available;
        last;
    }

    unless ($has_waited) {
        print STDERR defined($requested_slot)
            ? "Waiting for DerivedData slot $requested_slot...\n"
            : "Waiting for a free DerivedData slot (all three are busy)...\n";
        $has_waited = 1;
    }
    sleep 0.2;
}

my $path = $selected->{path};
make_path($path);
open my $metadata, ">", "$path.checkout" or die "Cannot write $path.checkout: $!\n";
print {$metadata} $checkout or die "Cannot write $path.checkout: $!\n";
close $metadata or die "Cannot close $path.checkout: $!\n";

# Crashlytics expects `SourcePackages` inside DerivedData, and parallel slots need separate checkouts
print STDERR "DerivedData: $path\n";
my $test_logs = "$path/Logs/Test";
my %old_bundles = map { $_ => 1 } bundles_in($test_logs);
my $signals = POSIX::SigSet->new(SIGHUP, SIGINT, SIGTERM);
my $previous_signals = POSIX::SigSet->new();
sigprocmask(SIG_BLOCK, $signals, $previous_signals) or die "Cannot block signals: $!\n";

# The guard holds the lock until xcodebuild exits, even if the wrapper is killed
my $pid = fork();
die "Cannot fork lock guard: $!\n" unless defined($pid);
my $is_wrapper = $pid != 0;
if ($pid == 0) {
    $pid = fork();
    die "Cannot fork xcodebuild: $!\n" unless defined($pid);
    if ($pid == 0) {
        close $selected->{lock} or die "Cannot close $path.lock: $!\n";
        sigprocmask(SIG_SETMASK, $previous_signals) or die "Cannot restore signals: $!\n";
        exec "xcodebuild", @ARGV, "-derivedDataPath", $path;
        die "Cannot run xcodebuild: $!\n";
    }
} else {
    close $selected->{lock} or die "Cannot close $path.lock: $!\n";
}

for my $signal (qw(TERM INT HUP)) {
    $SIG{$signal} = sub { kill $signal, $pid; };
}
sigprocmask(SIG_SETMASK, $previous_signals) or die "Cannot restore signals: $!\n";

while (waitpid($pid, 0) == -1) {
    next if $! == EINTR;
    die "Cannot wait for child: $!\n";
}
my $code = $? & 127 ? 128 + ($? & 127) : $? >> 8;
# Only the guard still holds the slot lock, so only it may read result bundles in the slot
exit($code) if $is_wrapper;
# Only an actual test run leaves results to check; build-for-testing and -enumerate-tests run none
exit($code) if $code != 0 || !@filters || !$runs_tests || $enumerates;

# xcodebuild reports TEST SUCCEEDED even when a filter matched nothing, e.g. a suite nested in another one
unless (defined $result_bundle) {
    my @new = grep { !$old_bundles{$_} } bundles_in($test_logs);
    ($result_bundle) = sort { (stat($b))[9] <=> (stat($a))[9] } @new;
}
die "No result bundle found in $test_logs to check -only-testing against.\n" unless defined $result_bundle;

open my $results, "-|", "xcrun", "xcresulttool", "get", "test-results", "tests", "--path", $result_bundle, "--compact"
    or die "Cannot run xcresulttool: $!\n";
my $tree = decode_json(do { local $/; <$results> });
close $results or die "xcresulttool failed for $result_bundle\n";

my @cases;
my $walk;
$walk = sub {
    my ($node, $bundle) = @_;
    my $type = $node->{nodeType} // "";
    $bundle = $node->{name} if $type =~ /test bundle\z/;
    push @cases, [$bundle, $node->{nodeIdentifier} // ""] if $type eq "Test Case" && defined $bundle;
    $walk->($_, $bundle) for @{ $node->{children} // [] };
};
$walk->($_, undef) for @{ $tree->{testNodes} // [] };

my @unmatched = grep {
    my ($bundle, $test) = split m{/}, $_, 2;
    !grep {
        $_->[0] eq $bundle
            && (!defined $test || $_->[1] eq $test || index($_->[1], "$test/") == 0 || index($_->[1], "$test(") == 0)
    } @cases;
} @filters;
if (@unmatched) {
    print STDERR "-only-testing matched no tests: ", join(", ", @unmatched), "\n";
    print STDERR "A suite declared inside another one is addressed through the outer name, e.g. Bundle/Outer/Inner.\n";
    exit 65;
}
exit 0;

sub bundles_in {
    my ($dir) = @_;
    opendir(my $handle, $dir) or return ();
    my @found = map { "$dir/$_" } grep { /\.xcresult\z/ } readdir($handle);
    closedir $handle;
    return @found;
}
' -- "$@"
