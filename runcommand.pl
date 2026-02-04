#!/usr/bin/env perl
use Mojolicious::Lite;
use File::stat;
use File::Find;
use Mojo::IOLoop::Subprocess;

# Enable CORS for all routes
under sub {
    my $c = shift;
    $c->res->headers->header('Access-Control-Allow-Origin'  => '*');
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
    $c->res->headers->header('Access-Control-Allow-Headers' => 'Content-Type');
    return 1;
};

# Handle preflight OPTIONS requests
options '/setpermissions' => sub {
    my $c = shift;
    $c->res->headers->header('Access-Control-Allow-Origin'  => '*');
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
    $c->res->headers->header('Access-Control-Allow-Headers' => 'Content-Type');
    $c->render(text => '', status => 200);
};

# Route to run chmod asynchronously
post '/setpermissions' => sub {
    my $c   = shift;
    my $dir = $c->param('dir') || '/home/aagarwalAnubhav/BackupVMTest';

    unless (-d $dir) {
        return $c->render(json => { success => 0, message => "Directory not found: $dir" });
    }

    my $needs_update = 0;
    find(
        sub {
            my $st = stat($_) or return;
            my $mode = sprintf("%04o", $st->mode & 07777);
            if (-d $_) {
                $needs_update = 1 if $mode ne '0755';
            } else {
                $needs_update = 1 if $mode ne '0644';
            }
        },
        $dir
    );

    if (!$needs_update) {
        return $c->render(json => { success => 1, message => "All permissions already safe under $dir" });
    }

    my $subprocess = Mojo::IOLoop::Subprocess->new;
    $subprocess->run(
        sub {
            my $subproc = shift;
            # Run chmod recursively: dirs=755, files=644
            # Remove 'sudo' here; run app with sufficient privileges or configure sudoers
            my $cmd = "find $dir -type d -exec chmod 755 {} \\; -o -type f -exec chmod 644 {} \\; 2>&1";
            my $output = `$cmd`;
            my $status = $? >> 8;
            return [$status, $output];   # ✅ return arrayref
        },
        sub {
            my ($subproc, $err, $result) = @_;
            my ($status, $output) = @$result if $result;

            if ($err) {
                $c->render(json => { success => 0, message => "Error running chmod: $err" });
            } elsif (defined $status && $status == 0) {
                $c->render(json => { success => 1, message => "Permissions updated safely for $dir" });
            } else {
                $c->render(json => { success => 0, message => "Failed to run chmod: $output" });
            }
        }
    );
};

app->start('daemon', '-l', 'http://*:8084');

