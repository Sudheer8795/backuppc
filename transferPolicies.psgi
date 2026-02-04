use strict;
use warnings;
use Plack::Request;
use JSON qw(encode_json decode_json);

my $FILE = "/home/aagarwalAnubhav/transferPolicies.json";

my @CORS_HEADERS = (
    'Access-Control-Allow-Origin'  => '*',
    'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
    'Access-Control-Max-Age'       => '86400'
);

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    # Handle preflight (CORS)
    if ($req->method eq 'OPTIONS') {
        return [
            204,
            \@CORS_HEADERS,
            []
        ];
    }

    # GET → read file
    if ($req->method eq 'GET') {
        my $json = '{}';

        if (-e $FILE) {
            open my $fh, '<', $FILE;
            local $/;
            $json = <$fh>;
            close $fh;
        }

        return [
            200,
            [
              @CORS_HEADERS,
              'Content-Type' => 'application/json'
            ],
            [$json]
        ];
    }

    # POST → save file
    if ($req->method eq 'POST') {
        my $data;

        eval {
            $data = decode_json($req->content);
        };
        if ($@) {
            return [
                400,
                [
                  @CORS_HEADERS,
                  'Content-Type' => 'application/json'
                ],
                [encode_json({ error => 'Invalid JSON' })]
            ];
        }

        open my $fh, '>', $FILE or return [
            500,
            [
              @CORS_HEADERS,
              'Content-Type' => 'application/json'
            ],
            [encode_json({ error => "Cannot write file" })]
        ];

        print $fh encode_json($data);
        close $fh;

        return [
            200,
            [
              @CORS_HEADERS,
              'Content-Type' => 'application/json'
            ],
            [encode_json({ status => 'saved' })]
        ];
    }

    return [
        405,
        [
          @CORS_HEADERS,
          'Content-Type' => 'text/plain'
        ],
        ['Method Not Allowed']
    ];
};

$app;

