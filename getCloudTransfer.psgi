#!/usr/bin/env perl
use strict;
use warnings;
use JSON;
use Plack::Request;

my $FILE = "/home/aagarwalAnubhav/cloudTransfer.json";

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    # ---- CORS HEADERS ----
    my @cors_headers = (
        'Access-Control-Allow-Origin'  => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
    );

    # Handle preflight OPTIONS request
    if ($req->method eq 'OPTIONS') {
        return [ 200, \@cors_headers, [] ];
    }

    # Read JSON file
    open my $fh, '<', $FILE
        or return [
            500,
            [ 'Content-Type' => 'application/json', @cors_headers ],
            [ encode_json({ error => 'Cannot open file' }) ]
        ];

    local $/;
    my $json_text = <$fh>;
    close $fh;

    my $data = decode_json($json_text);

    # Filter by IP if provided
    if (my $ip = $req->param('ip')) {
        return [
            404,
            [ 'Content-Type' => 'application/json', @cors_headers ],
            [ encode_json({ error => 'IP not found' }) ]
        ] unless exists $data->{$ip};

        return [
            200,
            [ 'Content-Type' => 'application/json', @cors_headers ],
            [ encode_json({ $ip => $data->{$ip} }) ]
        ];
    }

    # Return all data
    return [
        200,
        [ 'Content-Type' => 'application/json', @cors_headers ],
        [ encode_json($data) ]
    ];
};

$app;

