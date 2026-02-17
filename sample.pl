#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Encode;
use Getopt::Long;
use File::Basename;
use POSIX qw(strftime);

if ($^O eq 'MSWin32') {
    system("chcp 65001 >nul 2>&1");
}
binmode STDOUT, ':encoding(utf-8)';
binmode STDERR, ':encoding(utf-8)';

use FindBin qw($Bin);
require "$Bin/Utils.pl";
require "$Bin/AttendanceCalculator.pl";
require "$Bin/ReportFormatter.pl";

my $verbose        = 0;
my $output_file    = '';
my $input_file     = '';
my $base_date      = strftime("%Y-%m-%d", localtime);
my $retirement_age = 60;

my %DEPT_MASTER = (
    'D001' => '総務部',
    'D002' => '人事部',
    'D003' => '経理部',
    'D004' => '情報システム部',
    'D005' => '営業部',
    'D006' => '製造部',
    'D007' => '品質管理部',
    'D008' => '研究開発部',
);

sub parse_arguments {
    GetOptions(
        'verbose|v'      => \$verbose,
        'output|o=s'     => \$output_file,
        'input|i=s'      => \$input_file,
        'date|d=s'       => \$base_date,
        'retirement|r=i' => \$retirement_age,
        'help|h'         => \&show_help,
    ) or die "Error in command line arguments\n";

    Utils::set_verbose($verbose);
}

sub show_help {
    my $script_name = basename($0);
    print <<HELP;
Usage: $script_name [options]

社員データCSVを読み込み、各種集計レポート（勤怠含む）を出力します。

CSV形式: 社員番号,氏名,部署コード,入社日,生年月日,役職
  例: EMP001,山田太郎,D004,2005-04-01,1980-06-15,主任

Options:
    -v, --verbose           詳細出力モード
    -o, --output FILE       レポートをファイルに出力
    -i, --input FILE        入力CSVファイル指定
    -d, --date YYYY-MM-DD   基準日（デフォルト: 今日）
    -r, --retirement AGE    定年年齢（デフォルト: 60）
    -h, --help              このヘルプを表示

Example:
    $script_name -i employees.csv -o report.txt
    $script_name -v -i employees.csv -d 2026-03-31
HELP
    exit 0;
}

sub read_employee_data {
    my ($filename) = @_;
    my @employees;

    open(my $fh, '<:encoding(utf-8)', $filename) or die "Cannot open $filename: $!";
    my $line_num = 0;
    while (my $line = <$fh>) {
        $line_num++;
        chomp $line;

        $line =~ s/^\x{FEFF}// if $line_num == 1;

        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;

        my @fields = split(/,/, $line);
        if (scalar(@fields) != 6) {
            warn "Warning: Line $line_num: invalid format (skipped): $line\n";
            next;
        }

        my ($emp_id, $name, $dept_code, $hire_date, $birth_date, $position) = @fields;

        unless ($hire_date =~ /^\d{4}-\d{2}-\d{2}$/ && $birth_date =~ /^\d{4}-\d{2}-\d{2}$/) {
            warn "Warning: Line $line_num: invalid date format (skipped): $line\n";
            next;
        }

        my $dept_name = $DEPT_MASTER{$dept_code} || "不明($dept_code)";

        push @employees, {
            emp_id     => $emp_id,
            name       => $name,
            dept_code  => $dept_code,
            dept_name  => $dept_name,
            hire_date  => $hire_date,
            birth_date => $birth_date,
            position   => $position,
            age        => Utils::calc_age($birth_date, $base_date),
            years      => Utils::calc_age($hire_date, $base_date),
        };
    }
    close($fh);

    Utils::log_message("Read $line_num lines, parsed " . scalar(@employees) . " employee records");
    return @employees;
}

sub aggregate_by_department {
    my (@employees) = @_;
    my %summary;

    foreach my $emp (@employees) {
        my $dept = $emp->{dept_name};
        $summary{$dept}{count}++;
        $summary{$dept}{total_years} += $emp->{years};
        $summary{$dept}{positions}{$emp->{position}}++;
    }

    return %summary;
}

sub calc_service_distribution {
    my (@employees) = @_;
    my %dist = (
        '0-4年'    => 0,
        '5-9年'    => 0,
        '10-19年'  => 0,
        '20-29年'  => 0,
        '30年以上' => 0,
    );

    foreach my $emp (@employees) {
        my $y = $emp->{years};
        if    ($y < 5)  { $dist{'0-4年'}++; }
        elsif ($y < 10) { $dist{'5-9年'}++; }
        elsif ($y < 20) { $dist{'10-19年'}++; }
        elsif ($y < 30) { $dist{'20-29年'}++; }
        else            { $dist{'30年以上'}++; }
    }

    return %dist;
}

sub find_upcoming_retirements {
    my ($fiscal_year_end, @employees) = @_;
    my @retirees;

    foreach my $emp (@employees) {
        my $age_at_end = Utils::calc_age($emp->{birth_date}, $fiscal_year_end);
        if ($age_at_end >= $retirement_age) {
            push @retirees, { %$emp, age_at_retirement => $age_at_end };
        }
    }

    return sort { $a->{birth_date} cmp $b->{birth_date} } @retirees;
}

sub build_attendance_data {
    my (@employees) = @_;
    my %attendance;

    my %sample_records = (
        'EMP001' => [
            ["2025-01-06","09:00","18:00"], ["2025-01-07","09:00","19:30"],
            ["2025-01-08","09:00","18:00"], ["2025-01-09","09:00","18:00"],
            ["2025-01-10","09:00","18:00"],
        ],
        'EMP002' => [
            ["2025-01-06","09:00","18:00"], ["2025-01-07","09:00","20:30"],
            ["2025-01-08","09:00","18:00"], ["2025-01-09","09:00","22:30"],
            ["2025-01-10","09:00","17:00"],
        ],
        'EMP005' => [
            ["2025-01-06","08:00","20:00"], ["2025-01-07","08:00","21:00"],
            ["2025-01-08","08:00","23:00"], ["2025-01-09","08:00","19:00"],
            ["2025-01-10","08:00","18:00"],
        ],
        'EMP010' => [
            ["2025-01-06","08:30","19:00"], ["2025-01-07","08:30","23:30"],
            ["2025-01-08","09:00","18:00"], ["2025-01-09","08:30","18:30"],
            ["2025-01-10","09:00","21:00"],
        ],
    );

    foreach my $emp (@employees) {
        my $id = $emp->{emp_id};
        next unless exists $sample_records{$id};

        my $calc = AttendanceCalculator->new(
            emp_id   => $id,
            emp_name => $emp->{name},
        );
        for my $rec (@{$sample_records{$id}}) {
            $calc->add_record($rec->[0], $rec->[1], $rec->[2]);
        }
        $attendance{$id} = $calc;
    }

    Utils::log_message("Built attendance data for " . scalar(keys %attendance) . " employees");
    return %attendance;
}

sub generate_sample_data {
    return (
        { emp_id => "EMP001", name => "山田太郎",   dept_code => "D004", dept_name => "情報システム部", hire_date => "1990-04-01", birth_date => "1966-08-12", position => "部長",   age => 0, years => 0 },
        { emp_id => "EMP002", name => "鈴木花子",   dept_code => "D004", dept_name => "情報システム部", hire_date => "2005-04-01", birth_date => "1982-03-25", position => "主任",   age => 0, years => 0 },
        { emp_id => "EMP003", name => "佐藤一郎",   dept_code => "D005", dept_name => "営業部",         hire_date => "2010-10-01", birth_date => "1987-11-03", position => "一般",   age => 0, years => 0 },
        { emp_id => "EMP004", name => "高橋美咲",   dept_code => "D003", dept_name => "経理部",         hire_date => "2015-04-01", birth_date => "1992-07-20", position => "一般",   age => 0, years => 0 },
        { emp_id => "EMP005", name => "田中健二",   dept_code => "D006", dept_name => "製造部",         hire_date => "1988-04-01", birth_date => "1965-01-30", position => "課長",   age => 0, years => 0 },
        { emp_id => "EMP006", name => "伊藤裕子",   dept_code => "D001", dept_name => "総務部",         hire_date => "2000-04-01", birth_date => "1977-12-08", position => "係長",   age => 0, years => 0 },
        { emp_id => "EMP007", name => "渡辺大輔",   dept_code => "D008", dept_name => "研究開発部",     hire_date => "2018-04-01", birth_date => "1995-05-14", position => "一般",   age => 0, years => 0 },
        { emp_id => "EMP008", name => "小林正義",   dept_code => "D005", dept_name => "営業部",         hire_date => "1995-04-01", birth_date => "1970-09-22", position => "課長",   age => 0, years => 0 },
        { emp_id => "EMP009", name => "加藤恵",     dept_code => "D002", dept_name => "人事部",         hire_date => "2020-04-01", birth_date => "1997-02-11", position => "一般",   age => 0, years => 0 },
        { emp_id => "EMP010", name => "吉田拓也",   dept_code => "D004", dept_name => "情報システム部", hire_date => "2012-04-01", birth_date => "1989-04-05", position => "主任",   age => 0, years => 0 },
        { emp_id => "EMP011", name => "中村由美",   dept_code => "D007", dept_name => "品質管理部",     hire_date => "2008-04-01", birth_date => "1984-10-18", position => "係長",   age => 0, years => 0 },
        { emp_id => "EMP012", name => "松本修",     dept_code => "D006", dept_name => "製造部",         hire_date => "1992-04-01", birth_date => "1968-03-07", position => "係長",   age => 0, years => 0 },
    );
}

sub main {
    parse_arguments();

    my @employees;
    if ($input_file) {
        @employees = read_employee_data($input_file);
    } else {
        @employees = generate_sample_data();
        Utils::log_message("入力ファイル未指定のため、サンプルデータを使用します");
    }

    die "Error: No valid employee records found.\n" if scalar(@employees) == 0;

    foreach my $emp (@employees) {
        $emp->{age}   = Utils::calc_age($emp->{birth_date}, $base_date);
        $emp->{years} = Utils::calc_age($emp->{hire_date}, $base_date);
    }

    my %by_dept = aggregate_by_department(@employees);
    my %dist    = calc_service_distribution(@employees);

    my $fiscal_year_end;
    if ($base_date =~ /^(\d{4})-(\d{2})/) {
        my ($y, $m) = ($1, $2);
        $fiscal_year_end = ($m <= 3) ? "$y-03-31" : ($y + 1) . "-03-31";
    } else {
        $fiscal_year_end = "2027-03-31";
    }
    my @retirees = find_upcoming_retirements($fiscal_year_end, @employees);

    my %attendance = build_attendance_data(@employees);

    my $formatter = ReportFormatter->new(
        base_date      => $base_date,
        retirement_age => $retirement_age,
    );
    my @report = $formatter->generate_report(\@employees, \%by_dept, \%dist, \@retirees, \%attendance);

    if ($output_file) {
        $formatter->write_report($output_file, @report);
        print "レポートを $output_file に出力しました。\n";
    } else {
        print "$_\n" for @report;
    }
}

main() unless caller;

1;
