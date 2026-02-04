use strict;
use warnings;
use Plack::Request;
use JSON qw(decode_json encode_json);
use File::Path qw(make_path);
use File::Basename;
use Fcntl qw(:flock);

my $JSON_FILE = "/home/aagarwalAnubhav/cloudTransfer.json";

# ---------------- CORS ----------------
sub cors_headers {
    return [
        'Access-Control-Allow-Origin'  => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
        'Access-Control-Max-Age'        => '86400',
    ];
}

# ---------------- FILE HELPERS ----------------
sub load_all {
    return {} unless -f $JSON_FILE;

    open my $fh, '<', $JSON_FILE or return {};
    flock($fh, LOCK_SH);

    local $/;
    my $json = <$fh>;

    flock($fh, LOCK_UN);
    close $fh;

    return {} unless defined $json && $json =~ /\S/;

    my $data;
    eval { $data = decode_json($json); };
    return {} if $@ || ref $data ne 'HASH';

    return $data;
}

sub save_all {
    my ($data) = @_;

    my $dir = dirname($JSON_FILE);
    make_path($dir) unless -d $dir;

    open my $fh, '>', $JSON_FILE or die "Cannot write $JSON_FILE: $!";
    flock($fh, LOCK_EX);

    print $fh encode_json($data);

    flock($fh, LOCK_UN);
    close $fh;
}

sub extract_host {
    my ($arr) = @_;
    for my $item (@$arr) {
        return $item->{value}
            if $item->{label} eq 'host' && defined $item->{value};
    }
    return undef;
}

# ---------------- APP ----------------
my $app = sub {
    my $req = Plack::Request->new(shift);

    # ---- PREFLIGHT ----
    if ($req->method eq 'OPTIONS') {
        return [ 200, cors_headers(), [] ];
    }

    # ---- SAVE PER HOST ----
    if ($req->path eq '/save' && $req->method eq 'POST') {

        my $incoming;
        eval { $incoming = decode_json($req->content); };

        if ($@ || ref $incoming ne 'ARRAY') {
            return [
                400,
                [ @{ cors_headers() }, 'Content-Type' => 'application/json' ],
                [ encode_json({ error => "Invalid JSON payload" }) ]
            ];
        }

        my $host = extract_host($incoming);
        unless ($host) {
            return [
                400,
                [ @{ cors_headers() }, 'Content-Type' => 'application/json' ],
                [ encode_json({ error => "host label missing" }) ]
            ];
        }

        my $all = load_all();

        # remove host label before storing
        my @clean = grep { $_->{label} ne 'host' } @$incoming;

        $all->{$host} = {
            updated_at => time(),
            stats      => \@clean
        };

        save_all($all);

        return [
            200,
            [ @{ cors_headers() }, 'Content-Type' => 'application/json' ],
            [ encode_json({ status => "saved", host => $host }) ]
        ];
    }

    # ---- GET ALL HOSTS ----
    if ($req->path eq '/get' && $req->method eq 'GET') {
        my $all = load_all();

        return [
            200,
            [ @{ cors_headers() }, 'Content-Type' => 'application/json' ],
            [ encode_json($all) ]
        ];
    }

    # ---- 404 ----
    return [
        404,
        [ @{ cors_headers() }, 'Content-Type' => 'application/json' ],
        [ encode_json({ error => "Not Found" }) ]
    ];
};

$app;

