use strict;
use warnings;
use JSON;

my $CORS = [
    'Access-Control-Allow-Origin'  => '*',
    'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
    'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS'
];

# ---------- CRON → ONCALENDAR ----------
sub cron_to_oncalendar {
    my ($cron) = @_;
    return "" unless $cron;

    $cron =~ s/^\s+|\s+$//g;
    my ($min, $hour, $dom, $mon, $dow) = split /\s+/, $cron;
    return "" unless defined $dow;

    my %dow_map = (
        0 => 'Sun', 1 => 'Mon', 2 => 'Tue', 3 => 'Wed',
        4 => 'Thu', 5 => 'Fri', 6 => 'Sat', 7 => 'Sun',
        '*' => '*'
    );

    return "" unless exists $dow_map{$dow};

    $min  = sprintf("%02d", $min);
    $hour = sprintf("%02d", $hour);

    my $day = $dow_map{$dow};

    return "$day *-*-* $hour:$min:00";
}

# ---------- ONCALENDAR → CRON ----------
sub oncalendar_to_cron {
    my ($on) = @_;
    return "" unless $on;

    my %dow = (Sun=>0, Mon=>1, Tue=>2, Wed=>3, Thu=>4, Fri=>5, Sat=>6);

    if ($on =~ /^(\w+)\s+\*-\*-\*\s+(\d{2}):(\d{2}):00$/) {
        return "$3 $2 * * $dow{$1}";
    }

    return "";
}

# ---------- SYSTEMD ----------
sub get_oncalendar {
    my $out = `systemctl cat rclone-sync.timer 2>/dev/null`;
    return $1 if $out =~ /OnCalendar=(.+)/;
    return "";
}

sub get_next_run {
    my $out = `systemctl list-timers rclone-sync.timer --no-pager --no-legend 2>/dev/null`;
    return $1 if $out =~ /^(\S+\s+\S+)/;
    return "";
}

# ---------- PSGI ----------
sub {
    my $env = shift;
    my $method = $env->{REQUEST_METHOD} || '';

    return [200, $CORS, []] if $method eq 'OPTIONS';

    if ($method eq 'GET') {
        return [
            200,
            [ @$CORS, 'Content-Type' => 'application/json' ],
            [ encode_json({
                name       => 'Cloud Backup',
                cron       => oncalendar_to_cron(get_oncalendar()),
                oncalendar => get_oncalendar(),
                next_run   => get_next_run()
            }) ]
        ];
    }

    if ($method eq 'POST') {
        my $body = '';
        $env->{'psgi.input'}->read($body, 10240);

        my $data;
        eval { $data = decode_json($body) };

        if ($@ || ref($data) ne 'ARRAY' || !$data->[0]{cron}) {
            return [400, [ @$CORS, 'Content-Type' => 'application/json' ],
                [ encode_json({ error => 'Invalid JSON or cron missing' }) ]
            ];
        }

        my $cron = $data->[0]{cron};
        my $oncalendar = cron_to_oncalendar($cron);

        return [400, [ @$CORS, 'Content-Type' => 'application/json' ],
            [ encode_json({ error => 'Invalid cron format' }) ]
        ] unless $oncalendar;

        my $timer = <<"EOF";
[Unit]
Description=Run Rclone Sync

[Timer]
OnCalendar=$oncalendar
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # ✅ SAFE FILE WRITE (NO echo)
        open my $fh, "|-", "sudo tee /etc/systemd/system/rclone-sync.timer >/dev/null"
            or die "Cannot write timer";
        print $fh $timer;
        close $fh;

        system("sudo systemctl daemon-reload");
        system("sudo systemctl restart rclone-sync.timer");

        return [
            200,
            [ @$CORS, 'Content-Type' => 'application/json' ],
            [ encode_json({
                success    => JSON::true,
                cron       => $cron,
                oncalendar => $oncalendar
            }) ]
        ];
    }

    return [405, [ @$CORS, 'Content-Type' => 'application/json' ],
        [ encode_json({ error => 'Method Not Allowed' }) ]
    ];
};

