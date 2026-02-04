#!/usr/bin/env perl
use strict;
use warnings;
use Plack::Request;
use LWP::UserAgent;
use JSON qw(decode_json encode_json);
use Time::Piece;

my $RC_URL = "http://127.0.0.1:8082";

my $ua = LWP::UserAgent->new(
    timeout    => 10,
    keep_alive => 1,
);

# ---------------- RC CALL ----------------
sub rc_get {
    my ($endpoint, $payload) = @_;
    $payload ||= {};

    my $res = $ua->post(
        "$RC_URL$endpoint",
        'Content-Type' => 'application/json',
        Content        => encode_json($payload)
    );

    return undef unless $res->is_success;
    return decode_json($res->decoded_content);
}

# ---------------- REGION / BUCKET ----------------
sub extract_region_bucket {
    my ($cfg) = @_;
    return ("-", "-") unless $cfg && $cfg->{parameters};

    my $p = $cfg->{parameters};

    # AWS S3
    if ($cfg->{type} eq 's3') {
        return (
            $p->{region} // "-",
            $p->{bucket} // "-"
        );
    }

    # Azure Blob
    if ($cfg->{type} eq 'azureblob') {
        return (
            $p->{region} || $p->{location} || "-",
            $p->{container} || "-"
        );
    }

    # Google Cloud Storage
    if ($cfg->{type} =~ /google/i) {
        return (
            $p->{location} || $p->{region} || "-",
            $p->{bucket} || "-"
        );
    }

    return ("-", "-");
}

# ---------------- PSGI APP ----------------
my $app = sub {
    my $req = Plack::Request->new(shift);

    # ---- CORS ----
    if ($req->method eq 'OPTIONS') {
        return [ 200, cors_headers(), [] ];
    }

    return [ 405, cors_headers(), [ encode_json({ error => "Method not allowed" }) ] ]
        if $req->method ne 'GET';

    my $stats   = rc_get("/core/stats") || {};
    my $remotes = rc_get("/config/listremotes")->{remotes} || [];

    my @providers;
    my $total_bytes = 0;

    for my $remote (@$remotes) {
        (my $name = $remote) =~ s/:$//;

        my $size = rc_get("/operations/size", { fs => $remote }) || {};
        my $cfg  = rc_get("/config/get",      { name => $name }) || {};

        my ($region, $bucket) = extract_region_bucket($cfg);

        my $bytes = $size->{bytes} // 0;
        $total_bytes += $bytes;

        push @providers, {
            name       => uc($name),
            bucket     => $bucket,
            region     => $region,
            status     => "Healthy",
            storage_gb => sprintf("%.1f", $bytes / (1024**3)),
            objects    => $size->{count} // 0,
        };
    }

    my %overview = (
        total_storage_tb => sprintf("%.2f", $total_bytes / (1024**4)),
        hosts            => scalar @$remotes,
        last_transfer    => {
            time   => localtime($stats->{lastTransferTime} || time)->datetime,
            bytes  => sprintf("%.2f GB", ($stats->{bytes} || 0) / (1024**3)),
            status => "Success",
        },
        active_providers => scalar @providers,
        providers        => \@providers,
    );

    return [ 200, cors_headers(), [ encode_json(\%overview) ] ];
};

# ---------------- HEADERS ----------------
sub cors_headers {
    return [
        'Content-Type'                 => 'application/json',
        'Access-Control-Allow-Origin'  => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
    ];
}

$app;

