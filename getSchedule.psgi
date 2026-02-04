use strict;
use warnings;
use JSON;

# ---------------- READ TIMER ----------------
sub get_oncalendar {
    my $out = `systemctl cat rclone-sync.timer 2>/dev/null`;
    return $1 if $out =~ /OnCalendar=(.+)/;
    return "";
}

sub get_next_run {
    my $out = `systemctl list-timers rclone-sync.timer --no-pager --no-legend 2>/dev/null`;
    chomp $out;
    return $1 if $out =~ /^(\w+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/;
    return "";
}

# ---------------- ONCALENDAR → CRON ----------------
sub oncalendar_to_cron {
    my ($on) = @_;
    my %dow = (
        'Sun'=>0,'Mon'=>1,'Tue'=>2,'Wed'=>3,
        'Thu'=>4,'Fri'=>5,'Sat'=>6,'*'=>'*'
    );

    # Mon *-*-* 02:00:00 or 2:0:00
    if ($on =~ /^(\w+)\s+\*-\*-\*\s+(\d{1,2}):(\d{1,2}):00$/) {
        my ($d, $h, $m) = ($1, $2, $3);
        $h = int($h);
        $m = int($m);
        return "$m $h * * $dow{$d}";
    }

    # *-*-* 02:00:00
    if ($on =~ /^\*-\*-\*\s+(\d{1,2}):(\d{1,2}):00$/) {
        my ($h, $m) = ($1, $2);
        $h = int($h);
        $m = int($m);
        return "$m $h * * *";
    }

    # Mon *-1-1 02:00:00 (specific month/day)
    if ($on =~ /^(\w+)\s+\*-(\d+)-(\d+)\s+(\d{1,2}):(\d{1,2}):00$/) {
        my ($d, $mon, $dom, $h, $m) = ($1,$2,$3,$4,$5);
        $h = int($h);
        $m = int($m);
        return "$m $h $dom $mon $dow{$d}";
    }

    return "";
}

# ---------------- PSGI APP ----------------
sub {
    my $env = shift;

    # ---- OPTIONS (CORS preflight) ----
    if ($env->{REQUEST_METHOD} eq 'OPTIONS') {
        return [
            200,
            [
                'Access-Control-Allow-Origin' => '*',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
                'Access-Control-Allow-Methods' => 'GET, OPTIONS'
            ],
            []
        ];
    }

    # ---- GET (read schedule) ----
    if ($env->{REQUEST_METHOD} eq 'GET') {
        my $oncalendar = get_oncalendar();
        my $cron = oncalendar_to_cron($oncalendar);
        my $next = get_next_run();

        return [
            200,
            [ 
                'Content-Type' => 'application/json',
                'Access-Control-Allow-Origin'  => '*',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
                'Access-Control-Allow-Methods' => 'GET, OPTIONS'
            ],
            [ encode_json({
                name       => "Cloud Backup",
                cron       => $cron,
                oncalendar => $oncalendar,
                next_run   => $next
            }) ]
        ];
    }

    return [
        405,
        [ 'Access-Control-Allow-Origin' => '*' ],
        [ "Method Not Allowed" ]
    ];
};

