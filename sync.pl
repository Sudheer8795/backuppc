#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(encode_json decode_json);
use Fcntl qw(:flock);
use Time::HiRes qw(time sleep);

# ---------------- LOCK (prevent overlap) ----------------
open my $lock, ">/tmp/rclone-sync.lock" or die "Cannot open lock file";
flock($lock, LOCK_EX | LOCK_NB) or exit;

# ---------------- INPUT ----------------
die "Usage: perl sync.pl ip1,ip2\n" unless defined $ARGV[0];
my @ips = split(/\s*,\s*/, $ARGV[0]);

# ---------------- CONFIG ----------------
my $RC        = "http://127.0.0.1:8082";
my $SYNC_API  = "$RC/sync/copy";
my $STATS_API = "$RC/core/stats";
my $JSON_FILE = "/home/aagarwalAnubhav/cloudTransfer.json";

my $ua = LWP::UserAgent->new(
    timeout => 0,
    agent  => "rclone-sync/1.0"
);

# ---------------- LOAD JSON ----------------
my $store = {};
if (-f $JSON_FILE) {
    open my $fh, "<", $JSON_FILE;
    flock($fh, LOCK_SH);
    local $/;
    my $raw = <$fh>;
    close $fh;
    $store = decode_json($raw) if $raw;
}

# ---------------- SAVE JSON ----------------
sub save_json {
    open my $fh, ">", $JSON_FILE or die "Cannot write JSON";
    flock($fh, LOCK_EX);
    print $fh encode_json($store);
    close $fh;
}

# ---------------- GET CORE STATS ----------------
sub get_stats {
    my $res = $ua->post($STATS_API);
    return {} unless $res && $res->is_success;
    return decode_json($res->decoded_content);
}

# ---------------- RESET STATS ----------------
sub reset_stats {
    $ua->post(
        $STATS_API,
        'Content-Type' => 'application/json',
        Content => encode_json({ reset => JSON::true })
    );
}

# ================= MAIN LOOP =================
foreach my $ip (@ips) {

    my $src = "/home/aagarwalAnubhav/BackupVMTest/pc/$ip";
    my $dst = "azure:sudheer/BackupVMTest/pc/$ip";

    unless (-d $src) {
        warn "⏭ SKIPPED: source not found ($ip)\n";
        next;
    }

    print "▶ Sync started for $ip\n";

    # ---- reset + baseline stats ----
    reset_stats();
    sleep 1;
    my $before = get_stats();

    my $start = time();

    # ---- blocking sync ----
    my $res = $ua->post(
        "$SYNC_API?async=false",
        'Content-Type' => 'application/json',
        Content => encode_json({
            srcFs => $src,      # IMPORTANT: no "local:"
            dstFs => $dst,
            opt   => { retries => 3 }
        })
    );

    my $elapsed = int((time() - $start) * 1000);

    my $status = ($res && $res->is_success) ? "Success" : "Failed";

    # ---- final stats ----
    my $after = get_stats();

    my $bytes = ($after->{bytes}     // 0) - ($before->{bytes}     // 0);
    my $files = ($after->{transfers} // 0) - ($before->{transfers} // 0);

    $bytes = 0 if $bytes < 0;
    $files = 0 if $files < 0;

    # ---- store per host ----
    $store->{$ip} = {
        updated_at => time(),
        stats => [
            { label => "status",          value => $status },
            { label => "totalBytes",      value => $bytes },
            { label => "totalTransfers", value => $files },
            { label => "elapsedTime",     value => $elapsed }
        ]
    };

    save_json();

    print "✔ Saved stats for $ip ($status, $files files)\n";

    reset_stats();
    sleep 1;
}

print "✅ All sync jobs completed\n";

