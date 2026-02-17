#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin qw($Bin);
require "$Bin/Utils.pl";

package ReportFormatter;

sub new {
    my ($class, %opts) = @_;
    return bless {
        base_date      => $opts{base_date}      || "unknown",
        retirement_age => $opts{retirement_age}  || 60,
    }, $class;
}

sub generate_report {
    my ($self, $employees_ref, $dept_ref, $dist_ref, $retirees_ref, $attendance_ref) = @_;
    my @employees  = @$employees_ref;
    my %by_dept    = %$dept_ref;
    my %dist       = %$dist_ref;
    my @retirees   = @$retirees_ref;
    my %attendance = %$attendance_ref;

    my $base_date      = $self->{base_date};
    my $retirement_age = $self->{retirement_age};

    my @lines;
    push @lines, "=" x 60;
    push @lines, "        社 員 デ ー タ 集 計 レ ポ ー ト";
    push @lines, "=" x 60;
    push @lines, sprintf("  基準日: %s  /  対象者数: %d名", $base_date, scalar(@employees));
    push @lines, "";

    push @lines, $self->_format_department_section(\%by_dept);
    push @lines, $self->_format_distribution_section(\%dist);
    push @lines, $self->_format_retirement_section(\@retirees, $retirement_age);

    if (keys %attendance) {
        push @lines, $self->_format_attendance_section(\%attendance);
    }

    push @lines, "=" x 60;
    push @lines, sprintf("  総従業員数: %d名 / 平均年齢: %.1f歳 / 平均勤続: %.1f年",
        scalar(@employees),
        Utils::avg_field('age', @employees),
        Utils::avg_field('years', @employees));
    push @lines, "=" x 60;

    return @lines;
}

sub _format_department_section {
    my ($self, $by_dept_ref) = @_;
    my %by_dept = %$by_dept_ref;
    my @lines;

    push @lines, "【部署別人員構成】";
    push @lines, sprintf("  %-16s %6s %10s", "部署名", "人数", "平均勤続");
    push @lines, "  " . "-" x 36;
    foreach my $dept (sort keys %by_dept) {
        my $avg_years = $by_dept{$dept}{total_years} / $by_dept{$dept}{count};
        push @lines, sprintf("  %-16s %6d名 %8.1f年",
            $dept, $by_dept{$dept}{count}, $avg_years);
    }
    push @lines, "";

    return @lines;
}

sub _format_distribution_section {
    my ($self, $dist_ref) = @_;
    my %dist = %$dist_ref;
    my @lines;

    push @lines, "【勤続年数分布】";
    foreach my $range ('0-4年', '5-9年', '10-19年', '20-29年', '30年以上') {
        my $count = $dist{$range};
        my $bar = "#" x ($count * 2);
        push @lines, sprintf("  %-10s %3d名 %s", $range, $count, $bar);
    }
    push @lines, "";

    return @lines;
}

sub _format_retirement_section {
    my ($self, $retirees_ref, $retirement_age) = @_;
    my @retirees = @$retirees_ref;
    my @lines;

    push @lines, "【定年退職予定者（年度末時点で${retirement_age}歳以上）】";
    if (scalar(@retirees) == 0) {
        push @lines, "  該当者なし";
    } else {
        push @lines, sprintf("  %-8s %-10s %-14s %4s %s",
            "社員番号", "氏名", "部署", "年齢", "入社日");
        push @lines, "  " . "-" x 50;
        foreach my $r (@retirees) {
            push @lines, sprintf("  %-8s %-10s %-14s %4d歳 %s",
                $r->{emp_id}, $r->{name}, $r->{dept_name},
                $r->{age_at_retirement}, $r->{hire_date});
        }
        push @lines, sprintf("  → 計 %d名", scalar(@retirees));
    }
    push @lines, "";

    return @lines;
}

sub _format_attendance_section {
    my ($self, $attendance_ref) = @_;
    my %attendance = %$attendance_ref;
    my @lines;

    push @lines, "【勤怠集計（2025年1月 第2週サンプル）】";
    push @lines, sprintf("  %-8s %-10s %5s %6s %6s %6s %7s",
        "社員番号", "氏名", "出勤", "労働", "残業", "深夜", "残業率");
    push @lines, "  " . "-" x 58;
    foreach my $id (sort keys %attendance) {
        my $a = $attendance{$id};
        push @lines, sprintf("  %-8s %-10s %4d日 %5.1fh %5.1fh %5.1fh %5.1f%%",
            $a->emp_id(), $a->emp_name(), $a->working_days(),
            $a->total_work_hours(), $a->total_overtime_hours(),
            $a->total_late_night_hours(), $a->overtime_rate());
    }
    push @lines, "";

    return @lines;
}

sub write_report {
    my ($self, $filename, @lines) = @_;
    open(my $fh, '>:encoding(utf-8)', $filename) or die "Cannot open $filename for writing: $!";
    print $fh "$_\n" for @lines;
    close($fh);
    Utils::log_message("Report written to $filename");
}

1;
