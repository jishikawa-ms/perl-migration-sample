#!/usr/bin/perl

use strict;
use warnings;
use utf8;

package Utils;

sub calc_age {
    my ($from_date, $ref_date) = @_;
    return 0 unless $from_date =~ /^(\d{4})-(\d{2})-(\d{2})$/;
    my ($fy, $fm, $fd) = ($1, $2, $3);

    return 0 unless $ref_date =~ /^(\d{4})-(\d{2})-(\d{2})$/;
    my ($ry, $rm, $rd) = ($1, $2, $3);

    my $age = $ry - $fy;
    $age-- if ($rm < $fm) || ($rm == $fm && $rd < $fd);
    return $age;
}

sub time_to_minutes {
    my ($time_str) = @_;
    if ($time_str =~ /^(\d{1,2}):(\d{2})$/) {
        return $1 * 60 + $2;
    }
    die "Invalid time format: $time_str (expected HH:MM)\n";
}

my $_verbose = 0;

sub set_verbose {
    my ($flag) = @_;
    $_verbose = $flag;
}

sub is_verbose {
    return $_verbose;
}

sub log_message {
    my ($message) = @_;
    if ($_verbose) {
        my $timestamp = localtime();
        print STDERR "[$timestamp] $message\n";
    }
}

sub avg_field {
    my ($field, @records) = @_;
    return 0 if scalar(@records) == 0;
    my $total = 0;
    $total += $_->{$field} for @records;
    return $total / scalar(@records);
}

1;
