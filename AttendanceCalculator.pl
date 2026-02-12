#!/usr/bin/perl

use strict;
use warnings;
use utf8;

package AttendanceCalculator;

my $STANDARD_HOURS   = 8.0;
my $BREAK_HOURS      = 1.0;
my $LATE_NIGHT_START = 22;
my $LATE_NIGHT_END   = 5;

sub new {
    my ($class, %opts) = @_;
    return bless {
        emp_id   => $opts{emp_id}   || "UNKNOWN",
        emp_name => $opts{emp_name} || "不明",
        records  => [],
    }, $class;
}

sub add_record {
    my ($self, $date, $clock_in, $clock_out) = @_;

    die "add_record: date required\n"      unless $date;
    die "add_record: clock_in required\n"  unless $clock_in;
    die "add_record: clock_out required\n" unless $clock_out;

    my $in_minutes  = _time_to_minutes($clock_in);
    my $out_minutes = _time_to_minutes($clock_out);

    $out_minutes += 24 * 60 if $out_minutes <= $in_minutes;

    my $total_minutes = $out_minutes - $in_minutes;
    my $work_minutes  = $total_minutes - ($BREAK_HOURS * 60);
    $work_minutes = 0 if $work_minutes < 0;

    my $overtime_minutes = $work_minutes - ($STANDARD_HOURS * 60);
    $overtime_minutes = 0 if $overtime_minutes < 0;

    my $late_night_minutes = _calc_late_night_minutes($in_minutes, $out_minutes);

    push @{$self->{records}}, {
        date             => $date,
        clock_in         => $clock_in,
        clock_out        => $clock_out,
        work_hours       => $work_minutes / 60,
        overtime_hours   => $overtime_minutes / 60,
        late_night_hours => $late_night_minutes / 60,
    };
}

sub _time_to_minutes {
    my ($time_str) = @_;
    if ($time_str =~ /^(\d{1,2}):(\d{2})$/) {
        return $1 * 60 + $2;
    }
    die "Invalid time format: $time_str (expected HH:MM)\n";
}

sub _calc_late_night_minutes {
    my ($in_min, $out_min) = @_;
    my $late_night = 0;

    my $ln_start = $LATE_NIGHT_START * 60;
    my $ln_end   = (24 + $LATE_NIGHT_END) * 60;

    if ($out_min > $ln_start) {
        my $overlap_start = ($in_min > $ln_start) ? $in_min : $ln_start;
        my $overlap_end   = ($out_min < $ln_end)  ? $out_min : $ln_end;
        $late_night = $overlap_end - $overlap_start if $overlap_end > $overlap_start;
    }

    return $late_night;
}

sub working_days       { return scalar @{$_[0]->{records}}; }
sub emp_id             { return $_[0]->{emp_id}; }
sub emp_name           { return $_[0]->{emp_name}; }
sub records            { return @{$_[0]->{records}}; }

sub total_work_hours {
    my ($self) = @_;
    my $total = 0;
    $total += $_->{work_hours} for @{$self->{records}};
    return $total;
}

sub total_overtime_hours {
    my ($self) = @_;
    my $total = 0;
    $total += $_->{overtime_hours} for @{$self->{records}};
    return $total;
}

sub total_late_night_hours {
    my ($self) = @_;
    my $total = 0;
    $total += $_->{late_night_hours} for @{$self->{records}};
    return $total;
}

sub avg_work_hours {
    my ($self) = @_;
    return 0 if $self->working_days() == 0;
    return $self->total_work_hours() / $self->working_days();
}

sub overtime_rate {
    my ($self) = @_;
    my $standard_total = $self->working_days() * $STANDARD_HOURS;
    return 0 if $standard_total == 0;
    return ($self->total_overtime_hours() / $standard_total) * 100;
}

sub monthly_summary {
    my ($self) = @_;
    return sprintf(
        "[%s %s] 出勤: %d日 / 労働: %.1fh / 残業: %.1fh / 深夜: %.1fh / 残業率: %.1f%%",
        $self->emp_id(), $self->emp_name(),
        $self->working_days(),
        $self->total_work_hours(),
        $self->total_overtime_hours(),
        $self->total_late_night_hours(),
        $self->overtime_rate(),
    );
}

sub detail_lines {
    my ($self) = @_;
    my @lines;
    push @lines, sprintf("  %-12s %-6s %-6s %6s %6s %6s",
        "日付", "出勤", "退勤", "労働", "残業", "深夜");
    push @lines, "  " . "-" x 52;
    foreach my $rec (@{$self->{records}}) {
        push @lines, sprintf("  %-12s %-6s %-6s %5.1fh %5.1fh %5.1fh",
            $rec->{date}, $rec->{clock_in}, $rec->{clock_out},
            $rec->{work_hours}, $rec->{overtime_hours}, $rec->{late_night_hours});
    }
    return @lines;
}

1;
