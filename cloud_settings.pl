#!/usr/bin/env perl
use strict;
use warnings;

use Mojolicious::Lite;
use Mojolicious::Commands;

########################################
# CORS HANDLING
########################################
# ---------- CORS HANDLING ----------
hook before_dispatch => sub {
    my $c = shift;

    # Allow all origins
    $c->res->headers->header('Access-Control-Allow-Origin'  => '*');
    # Allow all relevant methods
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS');
    # Allow headers your frontend will send
    $c->res->headers->header('Access-Control-Allow-Headers' => 'Content-Type, Authorization');

    # Handle preflight OPTIONS requests
    if ($c->req->method eq 'OPTIONS') {
        $c->render(text => '', status => 200);
    }
};


########################################
# POST : SAVE CLOUD SETTINGS
########################################
post '/save-cloud-settings' => sub {
    my $c = shift;

    my $data = $c->req->json;

    return $c->render(
        json => { status => 'error', message => 'Invalid JSON body' },
        status => 400
    ) unless $data;

    my $instance = $data->{instanceName};   # rclone remote name
    my $type     = $data->{providerType};   # s3 | azureblob | drive
    my $region   = $data->{region};
    my $access   = $data->{accessKey};
    my $secret   = $data->{secretKey};

    # ---------- VALIDATION ----------
    return $c->render(
        json => { status => 'error', message => 'Instance name is required' },
        status => 400
    ) unless $instance;

    return $c->render(
        json => { status => 'error', message => 'Provider type is required' },
        status => 400
    ) unless $type;

    if ($type eq 's3') {
        return $c->render(
            json => { status => 'error', message => 'Missing S3 credentials or region' },
            status => 400
        ) unless $access && $secret && $region;
    }

    # ---------- BUILD RCLONE COMMAND ----------
    my @params;
    push @params, "access_key_id=$access"     if $access;
    push @params, "secret_access_key=$secret" if $secret;
    push @params, "region=$region"             if $region;
    push @params, "endpoint=$data->{endpoint}" if $data->{endpoint};

    my $cmd = "rclone config create $instance $type " .
              join(' ', @params) .
              " --non-interactive 2>&1";

    my $output = `$cmd`;

    if ($? != 0) {
        return $c->render(
            json => { status => 'error', message => $output },
            status => 500
        );
    }

    return $c->render(
        json => {
            status  => 'success',
            message => 'Cloud provider saved successfully',
            name    => $instance,
            type    => $type
        }
    );
};


########################################
# GET : READ REAL DATA FROM RCLONE
########################################
get '/get-cloud-configurations' => sub {
    my $c = shift;

    my $raw = `rclone config show 2>/dev/null`;
    return $c->render(json => [], status => 500) unless $raw;

    my @lines = split /\n/, $raw;

    my %current;
    my @result;

    sub check_remote_health {
        my ($remote) = @_;
        my $cmd = "rclone lsd $remote: --timeout 10s 2>/dev/null";
        system($cmd);
        return $? == 0 ? 'Healthy' : 'Unhealthy';
    }

    foreach my $line (@lines) {
        $line =~ s/^\s+|\s+$//g;

        # New remote block
        if ($line =~ /^\[(.+)\]$/) {
            if (%current) {
                $current{status} = check_remote_health($current{name});
                push @result, { %current };
            }

            %current = (
                name     => $1,      # instance name
                provider => '',
                region   => '',
            );
            next;
        }

        # Provider type
        if ($line =~ /^type\s*=\s*(.+)$/) {
            my $type = $1;

            $current{provider} =
                      $type eq 's3'                   ? 'AWS S3' :
                      $type eq 'azureblob'            ? 'Azure Blob' :
                      $type eq 'googlecloudstorage'   ? 'Google Cloud Storage' :
                      $type eq 'drive'                ? 'Google Drive' :
                      uc($type);

        }
        elsif ($line =~ /^provider\s*=\s*(.+)$/) {
            $current{provider} = $1;
        }
        elsif ($line =~ /^region\s*=\s*(.+)$/) {
            $current{region} = $1;
        }
        elsif ($line =~ /^endpoint\s*=\s*(.+)$/ && !$current{region}) {
            $current{region} = $1;
        }
    }

    if (%current) {
        $current{status} = check_remote_health($current{name});
        push @result, { %current };
    }

    return $c->render(json => \@result);
};

put '/update-cloud-settings/:name' => sub {
    my $c = shift;

    my $name = $c->param('name');
    my $data = $c->req->json;

    return $c->render(
        json => { status => 'error', message => 'Invalid JSON' },
        status => 400
    ) unless $data && $name;

    # Delete existing remote first
    my $delete_cmd = "rclone config delete $name 2>&1";
    my $delete_out = `$delete_cmd`;

    if ($? != 0) {
        return $c->render(
            json => { status => 'error', message => $delete_out },
            status => 500
        );
    }

    # Re-create remote
    my $type = $data->{type} || 's3';

    my @params;
    push @params, "access_key_id=$data->{accessKey}"     if $data->{accessKey};
    push @params, "secret_access_key=$data->{secretKey}" if $data->{secretKey};
    push @params, "bucket=$data->{bucketName}"           if $data->{bucketName};
    push @params, "region=$data->{region}"               if $data->{region};
    push @params, "endpoint=$data->{endpoint}"           if $data->{endpoint};

    my $cmd = "rclone config create $name $type " .
              join(' ', @params) .
              " --non-interactive 2>&1";

    my $out = `$cmd`;

    if ($? != 0) {
        return $c->render(
            json => { status => 'error', message => $out },
            status => 500
        );
    }

    return $c->render(
        json => { status => 'success', message => 'Provider updated', name => $name }
    );
};

del '/delete-cloud-settings/:name' => sub {
    my $c = shift;

    my $name = $c->param('name');

    return $c->render(
        json => { status => 'error', message => 'Provider name required' },
        status => 400
    ) unless $name;

    my $cmd = "rclone config delete $name 2>&1";
    my $out = `$cmd`;

    if ($? != 0) {
        return $c->render(
            json => { status => 'error', message => $out },
            status => 500
        );
    }

    return $c->render(
        json => { status => 'success', message => 'Provider deleted', name => $name }
    );
};



########################################
# START SERVER
########################################
app->start('daemon', '-l', 'http://0.0.0.0:8088');


