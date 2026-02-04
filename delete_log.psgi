use strict;
use warnings;
use Plack::Request;
use JSON;

my $LOG_FILE = '/home/aagarwalAnubhav/rcloneLog.txt';

sub cors_headers {
    return [
        'Access-Control-Allow-Origin'  => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, Authorization, X-Requested-With',
        'Access-Control-Max-Age'        => '86400',
        'Content-Type'                 => 'application/json',
    ];
}

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    # ---------- CORS Preflight ----------
    if ($req->method eq 'OPTIONS') {
        return [
            200,
            cors_headers(),
            [ encode_json({ status => 'ok' }) ]
        ];
    }

    # ---------- Method check ----------
    unless ($req->method =~ /^(POST|DELETE)$/) {
        return [
            405,
            cors_headers(),
            [ encode_json({ status => 'error', message => 'Method not allowed' }) ]
        ];
    }

    # ---------- File existence ----------
    unless (-e $LOG_FILE) {
        return [
            404,
            cors_headers(),
            [ encode_json({ status => 'error', message => 'Log file not found' }) ]
        ];
    }

    # ---------- Delete ----------
    if (unlink $LOG_FILE) {
        return [
            200,
            cors_headers(),
            [ encode_json({ status => 'success', message => 'Log file deleted permanently' }) ]
        ];
    } else {
        return [
            500,
            cors_headers(),
            [ encode_json({ status => 'error', message => "Delete failed: $!" }) ]
        ];
    }
};

$app;

