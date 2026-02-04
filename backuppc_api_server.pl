#!/usr/bin/perl
#============================================================= -*-perl-*-
#
# BackupPC_API_Server: A REST API server for BackupPC configuration
#
# DESCRIPTION
#
#   This script provides a REST API server that exposes BackupPC
#   configuration management functionality. It uses Plack/PSGI to serve
#   HTTP requests and integrates with BackupPC's existing authentication
#   and permission system.
#
#   Endpoints:
#     GET  /api/config  - Get general (main) configuration
#     PUT  /api/config  - Update general (main) configuration
#     GET  /api/hosts  - List all hosts
#     GET  /api/hosts/:hostname  - Get host details
#     POST /api/hosts  - Create new host
#     PUT  /api/hosts/:hostname  - Update host
#     DELETE /api/hosts/:hostname  - Delete host
#     GET  /api/backups  - List backups with status
#     POST /api/backups/:hostname/trigger  - Trigger backup
#     GET  /api/restore/:hostname/backups  - List backups for restore
#     GET  /api/restore/:hostname/backups/:backupNum/files  - Browse backup files
#     POST /api/restore/:hostname/backups/:backupNum/restore  - Initiate restore
#     GET  /api/reports/log-types  - Get log types
#     GET  /api/reports/logs/:logType/dates  - Get log dates
#     GET  /api/reports/logs/:logType/:date  - Get log content
#     GET  /api/notifications  - Get notification config
#     PUT  /api/notifications  - Update notification config
#     POST /api/restore/:hostname/backups/:backupNum/requests
#     POST /api/login - Verify user
#     POST /api/get-user-hosts
#
# AUTHOR
#   Generated for BackupPC API integration
#
# COPYRIGHT
#   Copyright (C) 2024
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#========================================================================

use strict;
use warnings;
use utf8;

# use lib "/home/aagarwalAnubhav/BackupPC/backuppc/lib";
use lib "/usr/share/BackupPC/lib";

use Plack::Request;
use Plack::Response;
use JSON;
use JSON::PP;
use BackupPC::Lib;
use BackupPC::View;
use BackupPC::DirOps qw(:BPC_DT_ALL);
use File::Basename;
use File::Path;
use File::Spec;
# Note: We don't import BackupPC::CGI::Lib functions directly
# to avoid conflicts, but we replicate the permission checking logic

# Initialize BackupPC library
our $bpc;
our $ConfigMTime;
my $GLOBAL_CONFIG_FILE = "/etc/backuppc/global-config.json";

# sub init_backuppc {
#     if ( !defined($bpc) ) {
#         $bpc = BackupPC::Lib->new(undef, undef, undef, 1);
#         if ( !$bpc ) {
#             die "Failed to initialize BackupPC::Lib. Check configuration.\n";
#         }
#         $ConfigMTime = $bpc->ConfigMTime();
#         umask($bpc->Conf()->{UmaskMode});
#     } elsif ( $bpc->ConfigMTime() != $ConfigMTime ) {
#         $bpc->ConfigRead();
#         $ConfigMTime = $bpc->ConfigMTime();
#         umask($bpc->Conf()->{UmaskMode});
#     }
# }
sub init_backuppc {
    if ( !defined($bpc) ) {
        $bpc = BackupPC::Lib->new(undef, undef, undef, 1)
            or die "Failed to init BackupPC::Lib";

        $bpc->ConfigRead();              # 🔥 FORCE CONFIG LOAD
        $ConfigMTime = $bpc->ConfigMTime();

        my $conf = $bpc->Conf();
        if (ref($conf) eq 'HASH' && exists $conf->{UmaskMode}) {
            umask($conf->{UmaskMode});
        }
    }
    elsif ( $bpc->ConfigMTime() != $ConfigMTime ) {
        $bpc->ConfigRead();              # 🔥 FORCE RELOAD
        $ConfigMTime = $bpc->ConfigMTime();

        my $conf = $bpc->Conf();
        if (ref($conf) eq 'HASH' && exists $conf->{UmaskMode}) {
            umask($conf->{UmaskMode});
        }
    }
}



# Get user from request (similar to BackupPC::CGI::Lib::NewRequest)
sub get_user {
    my $env = shift;

    my $remote_user;

    # If we really got a PSGI env hashref, use REMOTE_USER from there
    if (ref($env) eq 'HASH' && defined $env->{REMOTE_USER}) {
        $remote_user = $env->{REMOTE_USER};
    }

    # Safely get config hash
    my $conf = $bpc->Conf();
    $conf = {} unless ref($conf) eq 'HASH';
    my $default_user;
    if (ref($conf) eq 'HASH' && exists $conf->{BackupPCUser}) {
        $default_user = $conf->{BackupPCUser};
    }

    # Set REMOTE_USER in ENV for compatibility with BackupPC code
    $ENV{REMOTE_USER} = $remote_user || $default_user || "";

    my $user = $ENV{REMOTE_USER};

    # Handle LDAP uid=user when using mod_authz_ldap
    $user = $1 if ( $user =~ /uid=([^,]+)/i || $user =~ /(.*)/ );

    # Clean up %ENV for taint checking (like BackupPC does)
    delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
    $ENV{PATH} = $conf->{MyPath} if ref($conf) eq 'HASH' && exists $conf->{MyPath};

    return $user;
}

# Add CORS headers if needed
sub add_cors_headers {
    my $response = shift;
    $response->header('Access-Control-Allow-Origin' => '*');
    $response->header('Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS');
    $response->header('Access-Control-Allow-Headers' => 'Content-Type, Authorization');
    return $response;
}

# Check if user has permission for a specific host
sub check_host_permission {
    my ($user, $host) = @_;
    my $conf = $bpc->Conf();
    my $hosts = $bpc->HostInfoRead();
    
    # Admin has access to all hosts
    return 1 if ( check_admin_permission($user) );
    
    # Check if host exists
    return 0 if ( !defined($hosts->{lc($host)}) );
    
    # Check if user is the owner
    return 1 if ( $user eq $hosts->{lc($host)}{user} );
    
    # Check if user is in moreUsers
    my $moreUsers = $hosts->{lc($host)}{moreUsers} || "";
    if ( ref($moreUsers) eq "HASH" ) {
        return 1 if ( defined($moreUsers->{$user}) );
    } else {
        my %moreUsersHash = map { $_, 1 } split(/,/, $moreUsers);
        return 1 if ( defined($moreUsersHash{$user}) );
    }
    
    return 0;
}

# Extract path parameters from route pattern
sub extract_path_params {
    my ($path, $pattern) = @_;
    my %params = ();
    
    # Convert pattern to regex and extract parameter names
    my @param_names = ($pattern =~ /:(\w+)/g);
    my $regex = $pattern;
    $regex =~ s/:(\w+)/([^\/]+)/g;
    $regex =~ s/\//\\\//g;
    $regex = "^$regex\$";
    
    if ( $path =~ /$regex/ ) {
        my @matches = ($path =~ /$regex/);
        for ( my $i = 0; $i < @param_names && $i < @matches; $i++ ) {
            $params{$param_names[$i]} = $matches[$i] if ( defined($matches[$i]) );
        }
    }
    
    return %params;
}

# Connect to BackupPC server
sub server_connect {
    $bpc->ServerConnect();
    if ( !$bpc->ServerOK() ) {
        $bpc->ServerDisconnect();
        my $err = $bpc->ServerConnect($bpc->Conf()->{ServerHost}, $bpc->Conf()->{ServerPort});
        if ( defined($err) ) {
            return $err;
        }
    }
    return undef;
}

# TEMP: always allow admin access (for local/dev use only!)
 sub check_admin_permission {
    my $user = shift;
    return 1;
}


# Create JSON error response
sub json_error {
    my ($status, $message) = @_;
    my $json = JSON->new->utf8->pretty;
    my $response = Plack::Response->new($status);
    $response->content_type('application/json');
    $response->body($json->encode({ error => $message }));
    add_cors_headers($response);
    return $response->finalize;
}

# Create JSON success response
sub json_success {
    my ($data) = @_;
    my $json = JSON->new->utf8->pretty;
    my $response = Plack::Response->new(200);
    $response->content_type('application/json');
    $response->body($json->encode($data));
    add_cors_headers($response);
    return $response->finalize;
}

# use IPC::System::Simple qw(system);
use POSIX qw(WEXITSTATUS);

my $MOUNT_POINT = "/mnt/backuppc_storage";
my $CREDS_FILE  = "/var/lib/backuppc/.smb/backuppc.creds";

# sub mount_samba_storage {
#     my (%args) = @_;

#     my $ip       = $args{ip};
#     my $share    = $args{share};
#     my $username = $args{username};
#     my $password = $args{password};

#     # 1. Write credentials
#     system("mkdir -p /var/lib/backuppc/.smb");
#     open(my $fh, ">", $CREDS_FILE) or die "Cannot write creds file $CREDS_FILE: $!";
#     print $fh "username=$username\npassword=$password\n";
#     close($fh);
#     chmod 0600, $CREDS_FILE;

#     # 2. Unmount old mount (ignore errors)
#     system("umount $MOUNT_POINT >/dev/null 2>&1");

#     # 3. Mount new Samba share
#     my $cmd = "mount -t cifs //$ip/$share $MOUNT_POINT "
#             . "-o credentials=$CREDS_FILE,vers=3.0,"
#             . "uid=backuppc,gid=backuppc,file_mode=0770,dir_mode=0770";

#     system($cmd) == 0
#         or die "Failed to mount Samba share";

#     # 4. Restart BackupPC
#     system("systemctl restart backuppc") == 0
#         or die "Failed to restart BackupPC";
# }

# sub mount_samba_storage {
#     my (%args) = @_;

#     my $ip       = $args{ip};
#     my $share    = $args{share};
#     my $username = $args{username};
#     my $password = $args{password};

#     my $mount_point = "/mnt/backuppc_storage";
#     my $creds_dir   = "/var/lib/backuppc/.smb";
#     my $creds_file  = "$creds_dir/backuppc.creds";

#     # 1. Ensure dirs exist
#     system("sudo mkdir -p $creds_dir");
#     system("sudo mkdir -p $mount_point");

#     # 2. Write creds
#     open(my $fh, ">", $creds_file)
#         or die "Cannot write creds file";
#     print $fh "username=$username\npassword=$password\n";
#     close($fh);
#     chmod 0600, $creds_file;

#     # 3. SAFE unmount (ONLY if mounted)
#     system("mountpoint -q $mount_point && sudo umount $mount_point");

#     # 4. Mount
#     my $cmd = "mount -t cifs //$ip/$share $mount_point "
#             . "-o credentials=$creds_file,vers=3.0,"
#             . "uid=backuppc,gid=backuppc,file_mode=0770,dir_mode=0770";

#     system("sudo $cmd");
#     if ($? != 0) {
#         die "Failed to mount Samba share";
#     }

#     # 5. Restart BackupPC (non-fatal)
#     system("sudo systemctl restart backuppc");
# }
# sub mount_samba_storage {
#     my (%args) = @_;

#     my $ip       = $args{ip};
#     my $share    = $args{share};
#     my $username = $args{username};
#     my $password = $args{password};

#     my $mount_point = "/mnt/backuppc_storage";
#     my $creds_dir   = "/var/lib/backuppc/.smb";
#     my $creds_file  = "$creds_dir/backuppc.creds";

#     # 1. Ensure directories exist (NO sudo)
#     system("mkdir", "-p", $creds_dir) == 0
#         or die "Failed to create creds dir";

#     system("mkdir", "-p", $mount_point) == 0
#         or die "Failed to create mount point";

#     # 2. Write credentials
#     open(my $fh, ">", $creds_file)
#         or die "Cannot write creds file: $!";
#     print $fh "username=$username\npassword=$password\n";
#     close($fh);

#     chmod 0600, $creds_file
#         or die "Failed to chmod creds file";

#     # 3. Unmount only if mounted
#     system("mountpoint", "-q", $mount_point) == 0
#         and system("umount", $mount_point);

#     # 4. Mount with HARD TIMEOUT (10s)
#     my $cmd = "/usr/bin/timeout 10s "
#             . "/usr/sbin/mount.cifs //$ip/$share $mount_point "
#             . "-o credentials=$creds_file,vers=3.0,"
#             . "uid=backuppc,gid=backuppc,file_mode=0770,dir_mode=0770";

#     system("logger", "ISyncLite: starting SMB mount");
#     system($cmd);
#     my $exit = $? >> 8;
#     system("logger", "ISyncLite: mount finished with code $exit");

#     die "SMB mount failed or timed out" if $exit != 0;

#     # 5. Restart BackupPC (non-fatal)
#     system("systemctl", "restart", "backuppc");
# }
sub mount_samba_storage {
    my (%args) = @_;

    my $ip       = $args{ip};
    my $share    = $args{share};
    my $username = $args{username};
    my $password = $args{password};

    my $creds_dir  = "/var/lib/backuppc/.smb";
    my $creds_file = "$creds_dir/backuppc.creds";

    # 1. Write credentials (backuppc owns this)
    system("mkdir", "-p", $creds_dir) == 0
        or die "Failed to create creds dir";

    open(my $fh, ">", $creds_file)
        or die "Cannot write creds file: $!";
    print $fh "username=$username\npassword=$password\n";
    close($fh);

    chmod 0600, $creds_file
        or die "Failed to chmod creds file";

    # 2. Call ROOT mount helper (ONLY THIS)
    my $cmd = "/usr/bin/sudo /usr/local/bin/backuppc-mount.sh $ip $share";

    system("logger", "ISyncLite: starting SMB mount");
    system($cmd);
    my $exit = $? >> 8;
    system("logger", "ISyncLite: mount finished with code $exit");

    die "SMB mount failed" if $exit != 0;

    # 3. Restart BackupPC (non-fatal)
    system("systemctl", "restart", "backuppc");
}




# GET /api/config - Get general configuration
sub handle_get_config {
    my $env = shift;
    my $request = Plack::Request->new($env);
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Read general config (pass undef for host to get main config)
    my ($err, $config) = $bpc->ConfigDataRead();
    
    if ( defined($err) ) {
        return json_error(500, $err);
    }
    
    return json_success({ config => $config });
}

# PUT /api/config - Update general configuration
sub handle_put_config {
    my $env = shift;
    my $request = Plack::Request->new($env);
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Read request body
    my $body = $request->content;
    if ( !$body ) {
        return json_error(400, "Request body is required");
    }
    
    # Parse JSON
    my $json = JSON->new->utf8;
    my $data;
    eval {
        $data = $json->decode($body);
    };
    if ( $@ ) {
        return json_error(400, "Invalid JSON: $@");
    }
    
    # Validate that config key exists
    if ( !exists($data->{config}) || ref($data->{config}) ne "HASH" ) {
        return json_error(400, "Request must contain a 'config' object");
    }
    
    # Read current config to merge
    my ($readErr, $currentConfig) = $bpc->ConfigDataRead();
    if ( defined($readErr) ) {
        return json_error(500, "Failed to read current config: $readErr");
    }
    
    # Merge new config with current config
    my $newConfig = { %$currentConfig, %{$data->{config}} };
    
    # Write config (pass undef for host to write main config)
    my $writeErr = $bpc->ConfigDataWrite(undef, $newConfig);
    
    if ( defined($writeErr) ) {
        return json_error(500, $writeErr);
    }
    
    # Reload server to apply changes
    $bpc->ServerConnect();
    if ( $bpc->ServerOK() ) {
        $bpc->ServerMesg("server reload");
    }
    
    # Return updated config
    my ($finalErr, $finalConfig) = $bpc->ConfigDataRead();
    if ( defined($finalErr) ) {
        return json_error(500, "Config saved but failed to read back: $finalErr");
    }
    
    return json_success({ config => $finalConfig, message => "Configuration updated successfully" });
}
# POST /api/global-config
# sub handle_post_global_config {
#     my $env = shift;
#     my $request = Plack::Request->new($env);

#     init_backuppc();

#     my $user = get_user($env);
#     return json_error(403, "Admin access required")
#         unless check_admin_permission($user);

#     my $body = $request->content;
#     return json_error(400, "Request body required") unless $body;

#     my $data;
#     eval { $data = decode_json($body); };
#     return json_error(400, "Invalid JSON") if $@;

#     for my $key (qw/backupStoreIp backupShare backupUser backupPassword/) {
#         return json_error(400, "$key is required")
#             unless defined $data->{$key} && $data->{$key} ne "";
#     }

#     eval {
#         mount_samba_storage(
#             ip       => $data->{backupStoreIp},
#             share    => $data->{backupShare},
#             username => $data->{backupUser},
#             password => $data->{backupPassword},
#         );
#     };
#     if ($@) {
#         return json_error(500, "Global config failed: $@");
#     }

# # save config to disk
#     open my $fh, '>', $GLOBAL_CONFIG_FILE
#         or return json_error(500, "Cannot save global config");
#     print $fh encode_json($data);
#     close $fh;

#     return json_success({
#         success => 1,
#         message => "Backup storage configured successfully"
#     });


sub handle_post_global_config {
    my $env = shift;
    my $request = Plack::Request->new($env);

    init_backuppc();

    # ===============================
    # TEMP: HARDCODED C1 CONFIG (TEST)
    # ===============================
    my $C1_IP       = '192.168.1.15';
    my $C1_SHARE    = 'backuppc';
    my $C1_USER     = 'dell';
    my $C1_PASSWORD = 'Eice@987654321';

    # We ignore UI payload completely for now
    my $data = {
        backupStoreIp  => $C1_IP,
        backupShare    => $C1_SHARE,
        backupUser     => $C1_USER,
        backupPassword => $C1_PASSWORD,
    };

    # Try mounting SMB
    eval {
        mount_samba_storage(
            ip       => $C1_IP,
            share    => $C1_SHARE,
            username => $C1_USER,
            password => $C1_PASSWORD,
        );
    };
    if ($@) {
        my $err = $@;
        $err =~ s/\n/ /g;
        return json_error(500, "Hardcoded SMB mount failed: $err");
    }

    # Save config to disk (for GET later)
    open my $fh, '>', $GLOBAL_CONFIG_FILE
        or return json_error(500, "Cannot save global config file");
    print $fh encode_json($data);
    close $fh;

    return json_success({
        success => 1,
        message => "Global config saved (HARDCODED C1 TEST MODE)",
        storage => {
            ip    => $C1_IP,
            share => $C1_SHARE,
            user  => $C1_USER,
        }
    });
}


# GET /api/hosts - List all hosts
sub handle_get_hosts {
    my $env = shift;
    my $request = Plack::Request->new($env);
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission (or could allow users to see their own hosts)
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    my $hosts = $bpc->HostInfoRead();
    my @hostList = ();
    
    foreach my $host ( sort(keys(%$hosts)) ) {
        push(@hostList, {
            hostname => $host,
            dhcp => $hosts->{$host}{dhcp} || 0,
            user => $hosts->{$host}{user} || "",
            moreUsers => ref($hosts->{$host}{moreUsers}) eq "HASH" 
                ? join(",", keys(%{$hosts->{$host}{moreUsers}}))
                : ($hosts->{$host}{moreUsers} || "")
        });
    }
    
    return json_success(\@hostList);
}

# GET /api/hosts/:hostname - Get host details
sub handle_get_host {
    my $env     = shift;
    my $request = Plack::Request->new($env);
    my $path    = $request->path_info;

    init_backuppc();

    my $user = get_user($env);

    my %params   = extract_path_params($path, '/api/hosts/:hostname');
    my $hostname = lc($params{hostname} || "");

    if ( !$hostname ) {
        return json_error(400, "Hostname parameter required");
    }

    # Check permission for this host
    if ( !check_host_permission($user, $hostname) ) {
        return json_error(403, "Access denied for host $hostname");
    }

    # Get host info from hosts file
    my $hosts   = $bpc->HostInfoRead($hostname);
    
    my $lc_host = lc($hostname);

    if ( !defined $hosts->{$lc_host} ) {
        return json_error(404, "Host not found: $hostname");
    }

    my $hostInfo = $hosts->{$lc_host};

    # Get per-host config
    my ($err, $hostConfig) = $bpc->ConfigDataRead($hostname);
    if ( defined($err) || !defined $hostConfig || ref($hostConfig) ne 'HASH' ) {
        # Host config might not exist yet, or is not a hash – normalize to empty hashref
        $hostConfig = {};
    }

    my $conf = $bpc->Conf();
    if ( !defined $conf || ref($conf) ne 'HASH' ) {
        $conf = {};
    }
    my $smbPass = (defined $hostConfig->{SmbSharePasswd} && $hostConfig->{SmbSharePasswd} ne ''
              ? $hostConfig->{SmbSharePasswd}
              : undef)
       // (defined $hostConfig->{SmbSharePasswd} && $hostConfig->{SmbSharePasswd} ne ''
              ? $hostConfig->{SmbSharePasswd}
              : undef)
       // (defined $conf->{SmbSharePasswd} && $conf->{SmbSharePasswd} ne ''
              ? $conf->{SmbSharePasswd}
              : undef)
       // '';
    # ------------------------------------------------------------------
    # Retention counts – treat everything as simple scalars
    # ------------------------------------------------------------------

    my $fullKeepCnt =
          (defined $hostConfig->{ClientFullKeepCnt} && $hostConfig->{ClientFullKeepCnt} ne ''
              ? $hostConfig->{ClientFullKeepCnt}
              : undef)
       // (defined $hostConfig->{FullKeepCnt} && $hostConfig->{FullKeepCnt} ne ''
              ? $hostConfig->{FullKeepCnt}
              : undef)
       // (defined $conf->{FullKeepCnt} && $conf->{FullKeepCnt} ne ''
              ? $conf->{FullKeepCnt}
              : undef)
       // 1;

    my $incrKeepCnt =
          (defined $hostConfig->{ClientIncrKeepCnt} && $hostConfig->{ClientIncrKeepCnt} ne ''
              ? $hostConfig->{ClientIncrKeepCnt}
              : undef)
       // (defined $hostConfig->{IncrKeepCnt} && $hostConfig->{IncrKeepCnt} ne ''
              ? $hostConfig->{IncrKeepCnt}
              : undef)
       // (defined $conf->{IncrKeepCnt} && $conf->{IncrKeepCnt} ne ''
              ? $conf->{IncrKeepCnt}
              : undef)
       // 6;

    # ------------------------------------------------------------------
    # smbShare – also treat as simple scalar (no hash deref anywhere)
    # ------------------------------------------------------------------

    my $smbShare =
          (defined $hostConfig->{SmbShareName} && $hostConfig->{SmbShareName} ne ''
              ? $hostConfig->{SmbShareName}
              : undef)
       // (defined $hostConfig->{SmbShareName} && $hostConfig->{SmbShareName} ne ''
              ? $hostConfig->{SmbShareName}
              : undef)
       // (defined $conf->{SmbShareName} && $conf->{SmbShareName} ne ''
              ? $conf->{SmbShareName}
              : undef)
       // 'C$';

    # ------------------------------------------------------------------
    # Backup info (not used in response right now)
    # ------------------------------------------------------------------
    my @Backups = $bpc->BackupInfoRead($hostname);

    # ------------------------------------------------------------------
    # moreUsers field normalization
    # ------------------------------------------------------------------
    my $moreUsers = "";
    if ( ref($hostInfo->{moreUsers}) eq "HASH" ) {
        $moreUsers = join(",", keys %{ $hostInfo->{moreUsers} });
    } else {
        $moreUsers = $hostInfo->{moreUsers} || "";
    }
     # Resolve effective backup periods (host override -> global)
    my $fullBackupPeriod =
        (defined $hostConfig->{FullPeriod} && $hostConfig->{FullPeriod} ne ''
              ? $hostConfig->{FullPeriod}
              : undef)
       // (defined $hostConfig->{FullPeriod} && $hostConfig->{FullPeriod} ne ''
              ? $hostConfig->{FullPeriod}
              : undef)
       // (defined $conf->{FullPeriod} && $conf->{FullPeriod} ne ''
              ? $conf->{FullPeriod}
              : undef)
       // 6.97;

  my $incrBackupPeriod =
       (defined $hostConfig->{IncrPeriod} && $hostConfig->{IncrPeriod} ne ''
              ? $hostConfig->{IncrPeriod}
              : undef)
       // (defined $hostConfig->{IncrPeriod} && $hostConfig->{IncrPeriod} ne ''
              ? $hostConfig->{IncrPeriod}
              : undef)
       // (defined $conf->{IncrPeriod} && $conf->{IncrPeriod} ne ''
              ? $conf->{IncrPeriod}
              : undef)
       // 0.97;


    my $smbShareUserName =
       (defined $hostConfig->{SmbShareUserName} && $hostConfig->{SmbShareUserName} ne ''
              ? $hostConfig->{SmbShareUserName}
              : undef)
       // (defined $hostConfig->{SmbShareUserName} && $hostConfig->{SmbShareUserName} ne ''
              ? $hostConfig->{SmbShareUserName}
              : undef)
       // (defined $conf->{SmbShareUserName} && $conf->{SmbShareUserName} ne ''
              ? $conf->{SmbShareUserName}
              : undef)
       // '';


    # ------------------------------------------------------------------
    # Build response
    # ------------------------------------------------------------------
    my $response = {
        hostname => $hostname,
        dhcpFlag => $hostInfo->{dhcp} ? "1" : "0",
        user     => $hostInfo->{user} || "",
        moreUsers => $moreUsers,

        xferMethod    => $hostConfig->{XferMethod}
                      // $conf->{XferMethod}
                      // "rsync",

        clientCharset => $hostConfig->{ClientCharset}
                      // $conf->{ClientCharset}
                      // "",

        smbShare      => $smbShare,

        retentionFull => $fullKeepCnt,
        retentionIncr => $incrKeepCnt,
        smbPasswd => $smbPass,
        smbShareUserName => $smbShareUserName,

        # Note: Backup schedules are in WakeupSchedule, not per-host
        fullBackupPeriod => $fullBackupPeriod,    
        incrBackupPeriod => $incrBackupPeriod,  
    };

    return json_success($response);
}


# POST /api/hosts - Create new host
sub handle_post_hosts {
    my $env = shift;
    my $request = Plack::Request->new($env);
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Read request body
    my $body = $request->content;
    if ( !$body ) {
        return json_error(400, "Request body is required");
    }
    
    # Parse JSON
    my $json = JSON->new->utf8;
    my $data;
    eval {
        $data = $json->decode($body);
    };
    if ( $@ ) {
        return json_error(400, "Invalid JSON: $@");
    }
    
    my $hostname = lc($data->{hostname} || "");
    if ( !$hostname ) {
        return json_error(400, "hostname is required");
    }
    
    # Check if host already exists
    my $hosts = $bpc->HostInfoRead();
    if ( defined($hosts->{$hostname}) ) {
        return json_error(409, "Host already exists: $hostname");
    }
    
    # Add to hosts file
    $hosts->{$hostname} = {
        host => $hostname,
        dhcp => ($data->{dhcpFlag} || "0") eq "1" ? 1 : 0,
        user => $data->{user} || "",
        moreUsers => $data->{moreUsers} || ""
    };
    
    my $writeErr = $bpc->HostInfoWrite($hosts);
    if ( defined($writeErr) ) {
        return json_error(500, "Failed to write hosts file: $writeErr");
    }
    
    # Create per-host config if provided
    if ( $data->{xferMethod} || $data->{retentionFull} || $data->{retentionIncr} ) {
        my ($readErr, $hostConfig) = $bpc->ConfigDataRead($hostname);
        $hostConfig = {} if ( defined($readErr) );
        
        $hostConfig->{XferMethod} = $data->{xferMethod} if ( defined($data->{xferMethod}) );
        if ( defined($data->{retentionFull}) ) {
            $hostConfig->{ClientFullKeepCnt} = {} if ( ref($hostConfig->{ClientFullKeepCnt}) ne "HASH" );
            $hostConfig->{ClientFullKeepCnt}->{$hostname} = $data->{retentionFull};
        }
        if ( defined($data->{retentionIncr}) ) {
            $hostConfig->{ClientIncrKeepCnt} = {} if ( ref($hostConfig->{ClientIncrKeepCnt}) ne "HASH" );
            $hostConfig->{ClientIncrKeepCnt}->{$hostname} = $data->{retentionIncr};
        }
       # if ( defined($data->{clientCharset}) ) {
         #   $hostConfig->{ClientCharset} = {} if ( ref($hostConfig->{ClientCharset}) ne "HASH" );
         #   $hostConfig->{ClientCharset}->{$hostname} = $data->{clientCharset};
       # }
        if ( defined($data->{smbShare}) ) {
            $hostConfig->{ClientSmbShareName} = {} if ( ref($hostConfig->{ClientSmbShareName}) ne "HASH" );
            $hostConfig->{ClientSmbShareName}->{$hostname} = $data->{smbShare};
        }
        
        my $configErr = $bpc->ConfigDataWrite($hostname, $hostConfig);
        if ( defined($configErr) ) {
            return json_error(500, "Host created but failed to write config: $configErr");
        }
    }
    
    # Reload server
    server_connect();
    if ( $bpc->ServerOK() ) {
        $bpc->ServerMesg("server reload");
    }
    
    return json_success({ success => 1, message => "Host created successfully" });
}

# PUT /api/hosts/:hostname - Update host

sub handle_put_host {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;

    init_backuppc();

    my $user = get_user($env);

    my %params = extract_path_params($path, '/api/hosts/:hostname');
    my $hostname = lc($params{hostname} || "");

    if ( !$hostname ) {
        return json_error(400, "Hostname parameter required");
    }

    # Admin check
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }

    # Host exists check
    my $hosts = $bpc->HostInfoRead();
    if ( !defined($hosts->{$hostname}) ) {
        return json_error(404, "Host not found: $hostname");
    }

    # Read body
    my $body = $request->content;
    if ( !$body ) {
        return json_error(400, "Request body is required");
    }

    # Parse JSON
    my $json = JSON->new->utf8;
    my $data;
    eval { $data = $json->decode($body); };
    if ( $@ ) {
        return json_error(400, "Invalid JSON: $@");
    }
# ------------------ Update Host Info ------------------
    if ( defined($data->{dhcpFlag}) || defined($data->{user}) || defined($data->{moreUsers}) ) {
        # DHCP
        $hosts->{$hostname}{dhcp} = ($data->{dhcpFlag} || "0") eq "1" ? 1 : 0;

        # User
        $hosts->{$hostname}{user} = $data->{user} if defined($data->{user});


        my $writeErr = $bpc->HostInfoWrite($hosts);
        return json_error(500, "Failed to update hosts file: $writeErr") if defined($writeErr);
    }

    ############################
    # Read existing host config
    ############################
    my ($readErr, $hostConfig) = $bpc->ConfigDataRead($hostname);
    $hostConfig = {} if defined $readErr;

    my $configChanged = 0;


# SMB Share Name
if ( defined($data->{smbShare}) ) {
    $hostConfig->{SmbShareName} = $data->{smbShare};
    $configChanged = 1;
}

# SMB Username
if ( defined($data->{smbUserName}) ) {
    $hostConfig->{SmbShareUserName} = $data->{smbUserName};
    $configChanged = 1;
}

# SMB Password
if ( defined($data->{smbPasswd}) ) {
    $hostConfig->{SmbSharePasswd} = $data->{smbPasswd};
    $configChanged = 1;
}
# Full backup period (days)
if ( defined($data->{fullBackupPeriod}) ) {
    $hostConfig->{FullPeriod} = $data->{fullBackupPeriod} + 0;
    $configChanged = 1;
}

# Incremental backup period (days)
if ( defined($data->{incrBackupPeriod}) ) {
    $hostConfig->{IncrPeriod} = $data->{incrBackupPeriod} + 0;
    $configChanged = 1;
}


    ############################
    # Save config
    ############################
    if ( !$configChanged ) {
        return json_error(400, "No SMB fields provided to update");
    }

    my $configErr = $bpc->ConfigDataWrite($hostname, $hostConfig);
    if ( defined($configErr) ) {
        return json_error(500, "Failed to update SMB config: $configErr");
    }

    ############################
    # Reload BackupPC
    ############################
    server_connect();
    if ( $bpc->ServerOK() ) {
        $bpc->ServerMesg("server reload");
    }

    return json_success({
        success => 1,
        message => "SMB share override configuration saved successfully"
    });
}



# DELETE /api/hosts/:hostname - Delete host
sub handle_delete_host {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;
    
    init_backuppc();
    
    my $user = get_user($env);
    
    my %params = extract_path_params($path, '/api/hosts/:hostname');
    my $hostname = lc($params{hostname} || "");
    
    if ( !$hostname ) {
        return json_error(400, "Hostname parameter required");
    }
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Check if host exists
    my $hosts = $bpc->HostInfoRead();
    if ( !defined($hosts->{$hostname}) ) {
        return json_error(404, "Host not found: $hostname");
    }
    
    # Remove from hosts file
    delete($hosts->{$hostname});
    my $writeErr = $bpc->HostInfoWrite($hosts);
    if ( defined($writeErr) ) {
        return json_error(500, "Failed to delete host from hosts file: $writeErr");
    }
    
    # Note: Per-host config file is not deleted automatically
    # Could add logic to delete it if desired
    
    # Reload server
    server_connect();
    if ( $bpc->ServerOK() ) {
        $bpc->ServerMesg("server reload");
    }
    
    return json_success({ success => 1, message => "Host deleted successfully" });
}

# GET /api/backups - List backups with status
sub handle_get_backups {
    my $env = shift;
    my $request = Plack::Request->new($env);
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Connect to server and get status
    my $err = server_connect();
    if ( defined($err) ) {
        return json_error(500, "Failed to connect to BackupPC server: $err");
    }
    
    # Get status from server
    my $reply = $bpc->ServerMesg("status hosts");
    $reply = $1 if ( $reply =~ /(.*)/s );
    
    my %Status = ();
    eval($reply);
    
    # Get all hosts
    my $hosts = $bpc->HostInfoRead();
    my @backupList = ();
    
    foreach my $host ( sort(keys(%$hosts)) ) {
        my @Backups = $bpc->BackupInfoRead($host);
        my $lastBackup = "";
        my $status = "Unknown";
        my $backupType = "";
        my $backupNum = 0;
        
        if ( @Backups > 0 ) {
            my $latest = $Backups[@Backups - 1];
            $lastBackup = $bpc->timeStamp($latest->{startTime});
            $backupNum = $latest->{num};
            $backupType = $latest->{type} || "full";
        }
        
        # Check status from server
        if ( defined($Status{$host}) ) {
            my $stat = $Status{$host};
            if ( $stat->{state} eq "BackupInProgress" ) {
                $status = "Running";
            } elsif ( $stat->{state} eq "Idle" ) {
                $status = "Success";
            } else {
                $status = $stat->{state} || "Unknown";
            }
        } else {
            $status = @Backups > 0 ? "Success" : "Never";
        }
        
        push(@backupList, {
            hostname => $host,
            lastBackup => $lastBackup,
            status => $status,
            backupType => $backupType,
            backupNum => $backupNum
        });
    }
    
    return json_success(\@backupList);
}

# POST /api/backups/:hostname/trigger - Trigger backup
sub handle_post_backup_trigger {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;

    init_backuppc();

    my $user = get_user($env);

    my %params   = extract_path_params($path, '/api/backups/:hostname/trigger');
    my $hostname = lc($params{hostname} || "");

    if ( !$hostname ) {
        return json_error(400, "Hostname parameter required");
    }

    # Check if host exists
    my $hosts = $bpc->HostInfoRead();
    if ( !defined($hosts->{$hostname}) ) {
        return json_error(404, "Host not found: $hostname");
    }

    # If no user from auth, fall back to host owner or BackupPCUser
    if ( !$user ) {
        my $conf = $bpc->Conf();
        $user = $hosts->{$hostname}{user}
             || (ref($conf) eq 'HASH' ? ($conf->{BackupPCUser} || '') : '')
             || 'backuppc';
    }

    # Check permission for this host
    if ( !check_host_permission($user, $hostname) ) {
        return json_error(403, "Access denied for host $hostname");
    }

    # Read request body
    my $body = $request->content;
    my $data = {};
    if ( $body ) {
        my $json = JSON->new->utf8;
        eval {
            $data = $json->decode($body);
        };
    }

    my $type   = $data->{type} || "full";
    my $doFull = ($type eq "full") ? 1 : 0;

    # Connect to server
    my $err = server_connect();
    if ( defined($err) ) {
        return json_error(500, "Failed to connect to BackupPC server: $err");
    }

    # Trigger backup
    my $reply;
    if ( $hosts->{$hostname}{dhcp} ) {
        $reply = $bpc->ServerMesg("backup $hostname $hostname $user $doFull");
    } else {
        $reply = $bpc->ServerMesg("backup $hostname $hostname $user $doFull");
    }

    return json_success({
        success => 1,
        message => ucfirst($type) . " backup started for $hostname",
        reply   => $reply,
    });
}

# GET /api/restore/:hostname/backups - List backups for restore
sub handle_get_restore_backups {
    my $env     = shift;
    my $request = Plack::Request->new($env);
    my $path    = $request->path_info;

    init_backuppc();

    my $user = get_user($env);

    my %params   = extract_path_params($path, '/api/restore/:hostname/backups');
    my $hostname = lc($params{hostname} || "");

    if (!$hostname) {
        return json_error(400, "Hostname parameter required");
    }

    # Check permission for this host
    if (!check_host_permission($user, $hostname)) {
        return json_error(403, "Access denied for host $hostname");
    }

    # Get backup info
    my @Backups = $bpc->BackupInfoRead($hostname);
    my @backupList = ();

    foreach my $backup (@Backups) {
        push(@backupList, {
            backupNum => $backup->{num},
            startTime => $backup->{startTime},
            date      => $bpc->timeStamp($backup->{startTime}),
        });
    }

    return json_success(\@backupList);
}


# GET /api/restore/:hostname/backups/:backupNum/files - Browse backup files
sub handle_get_restore_files {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;
    
    init_backuppc();
    
    my $user = get_user($env);
    
    my %params = extract_path_params($path, '/api/restore/:hostname/backups/:backupNum/files');
    my $hostname = lc($params{hostname} || "");
    my $backupNum = $params{backupNum} || "";
    
    if ( !$hostname && !$backupNum ) {
        return json_error(400, "Hostname and backupNum parameters required");
    }
    
    # Check permission for this host
    if ( !check_host_permission($user, $hostname) ) {
        return json_error(403, "Access denied for host $hostname");
    }
    
    # Get query parameter for path
    my $queryPath = $request->parameters->get('path') || '/';
    
    # Get backups
    my @Backups = $bpc->BackupInfoRead($hostname);
    my $backup = undef;
    foreach my $b ( @Backups ) {
        if ( $b->{num} == $backupNum || $bpc->timeStamp($b->{startTime}) eq $backupNum ) {
            $backup = $b;
            last;
        }
    }
    
    if ( !defined($backup) ) {
        return json_error(404, "Backup not found");
    }
    
    # Use BackupPC::View to browse files
    my $view = BackupPC::View->new($bpc, $hostname, \@Backups, {nlink => 1});
    my $share2path = ref($backup->{share2path}) eq 'HASH' ? $backup->{share2path} : {};
    
    # Determine share and directory
    my $share = "";
    my $dir = $queryPath;
    $dir = "/$dir" if ( $dir !~ /^\// );
    
    # Get directory attributes
    my $attr = $view->dirAttrib($backup->{num}, $share, $dir);
    if ( !defined($attr) || keys(%$attr) == 0 ) {
        return json_error(404, "Directory not found: $dir");
    }
    
    # Get files in directory
    my @files = ();
    foreach my $file ( sort(keys(%$attr)) ) {
        my $fileAttr = $view->fileAttrib($backup->{num}, $share, "$dir/$file");
        my $isDir = ($fileAttr->{type} & BPC_DT_DIR) ? 1 : 0;
        
        push(@files, {
            name => $file,
            type => $isDir ? "folder" : "file",
            path => "$dir/$file",
            size => $isDir ? undef : ($fileAttr->{size} || 0),
            modified => $fileAttr->{mtime} ? $bpc->timeStamp($fileAttr->{mtime}) : undef
        });
    }
    
    return json_success(\@files);
}

# POST /api/restore/:hostname/backups/:backupNum/restore - Initiate restore
sub handle_post_restore {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;
    
    init_backuppc();
    
    my $user = get_user($env);
    
    my %params = extract_path_params($path, '/api/restore/:hostname/backups/:backupNum/restore');
    my $hostname = lc($params{hostname} || "");
    my $backupNum = $params{backupNum} || "";
    
    if ( !$hostname && !$backupNum ) {
        return json_error(400, "Hostname and backupNum parameters required");
    }
    
    # Check permission for this host
    if ( !check_host_permission($user, $hostname) ) {
        return json_error(403, "Access denied for host $hostname");
    }
    
    # Read request body
    my $body = $request->content;
    if ( !$body ) {
        return json_error(400, "Request body is required");
    }
    
    # Parse JSON
    my $json = JSON->new->utf8;
    my $data;
    eval {
        $data = $json->decode($body);
    };
    if ( $@ ) {
        return json_error(400, "Invalid JSON: $@");
    }
    
    if ( !defined($data->{files}) || ref($data->{files}) ne "ARRAY" || @{$data->{files}} == 0 ) {
        return json_error(400, "files array is required and must not be empty");
    }
    
    # Get backups to find the backup number
    my @Backups = $bpc->BackupInfoRead($hostname);
    my $backup = undef;
    my $num = 0;
    foreach my $b ( @Backups ) {
        if ( $b->{num} == $backupNum || $bpc->timeStamp($b->{startTime}) eq $backupNum ) {
            $backup = $b;
            $num = $b->{num};
            last;
        }
    }
    
    if ( !defined($backup) ) {
        return json_error(404, "Backup not found");
    }
    
    # Connect to server
    my $err = server_connect();
    if ( defined($err) ) {
        return json_error(500, "Failed to connect to BackupPC server: $err");
    }
    
    # Build restore command
    # Format: restore $num $host $share $pathHdr $user @fileList
    my $share = $backup->{share} || "";
    my $pathHdr = "/";
    my @fileList = @{$data->{files}};
    
    # Determine common path header
    if ( @fileList > 0 ) {
        $pathHdr = dirname($fileList[0]);
        foreach my $file ( @fileList ) {
            my $dir = dirname($file);
            while ( substr($dir, 0, length($pathHdr)) ne $pathHdr ) {
                $pathHdr = dirname($pathHdr);
            }
        }
    }
    $pathHdr = "/" if ( $pathHdr eq "" || $pathHdr eq "." );
    
    # Send restore command to server
    my $fileListStr = join(" ", map { "\"$_\"" } @fileList);
    $fileListStr =~ s/"//g;
    my $restoreCmd = "restore $num $hostname $share $pathHdr $user $fileListStr";
    my $reply = $bpc->ServerMesg($restoreCmd);
    
    return json_success({
        success => 1,
        message => "Restore initiated successfully",
        restoreId => "restore_${hostname}_${num}_" . time(),
        reply => $reply
    });
}



# GET /api/reports/log-types - Get log types
sub handle_get_log_types {
    my $env = shift;
    
    return json_success(["backup", "restore", "system"]);
}

# GET /api/reports/logs/:logType/dates - Get log dates
sub handle_get_log_dates {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    my %params = extract_path_params($path, '/api/reports/logs/:logType/dates');
    my $logType = $params{logType} || "";
    
    if ( $logType !~ /^(backup|restore|system)$/ ) {
        return json_error(400, "Invalid log type. Must be: backup, restore, or system");
    }
    
    my $logDir = $bpc->LogDir();
    my @dates = ();
    
    # Read log files
    opendir(my $dh, $logDir) || return json_error(500, "Cannot read log directory: $!");
    my @files = grep { /^LOG/ } readdir($dh);
    closedir($dh);
    
    # Sort by modification time (newest first)
    @files = sort { (stat("$logDir/$b"))[9] <=> (stat("$logDir/$a"))[9] } @files;
    
    foreach my $file ( @files ) {
        my $mtime = (stat("$logDir/$file"))[9];
        my $date = $bpc->timeStamp($mtime);
        $date =~ s/ .*//;  # Extract just the date part
        push(@dates, $date) if ( $date );
    }
    
    # Remove duplicates and sort
    my %seen = ();
    @dates = sort { $b cmp $a } grep { !$seen{$_}++ } @dates;
    
    return json_success(\@dates);
}

# GET /api/reports/logs/:logType/:date - Get log content
sub handle_get_log_content {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    my %params = extract_path_params($path, '/api/reports/logs/:logType/:date');
    my $logType = $params{logType} || "";
    my $date = $params{date} || "";
    
    if ( $logType !~ /^(backup|restore|system)$/ ) {
        return json_error(400, "Invalid log type");
    }
    
    my $logDir = $bpc->LogDir();
    my $logFile = "$logDir/LOG";
    
    # Try to find log file for the date
    if ( $date ne "" ) {
        # Look for LOG files matching the date
        opendir(my $dh, $logDir) || return json_error(500, "Cannot read log directory: $!");
        my @files = grep { /^LOG/ } readdir($dh);
        closedir($dh);
        
        foreach my $file ( @files ) {
            my $mtime = (stat("$logDir/$file"))[9];
            my $fileDate = $bpc->timeStamp($mtime);
            $fileDate =~ s/ .*//;
            if ( $fileDate eq $date ) {
                $logFile = "$logDir/$file";
                last;
            }
        }
    }
    
    # Read log file
    if ( !-f $logFile ) {
        return json_error(404, "Log file not found for date: $date");
    }
    
    open(my $fh, "<", $logFile) || return json_error(500, "Cannot read log file: $!");
    binmode($fh);
    my $content = do { local $/; <$fh> };
    close($fh);
    
    return json_success({
        content => $content,
        date => $date,
        type => $logType
    });
}

# GET /api/notifications - Get notification config
sub handle_get_notifications {
    my $env = shift;
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Read config and extract email settings
    my ($err, $config) = $bpc->ConfigDataRead();
    if ( defined($err) ) {
        return json_error(500, $err);
    }
    
    my $response = {
        emailFrom => $config->{EMailFromUserName} || "",
        emailTo => $config->{EMailAdminUserName} || "",
        sendReminders => ($config->{EMailNotifyMinDays} || 0) > 0 ? 1 : 0,
        reminderSchedule => "0 8 * * *",  # Default, would need to parse WakeupSchedule
        emailSubject => $config->{EMailAdminSubject} || "BackupPC Notification",
        emailBody => $config->{EMailNoBackupRecentMesg} || ""
    };
    
    return json_success($response);
}

# PUT /api/notifications - Update notification config
sub handle_put_notifications {
    my $env = shift;
    my $request = Plack::Request->new($env);
    
    init_backuppc();
    
    my $user = get_user($env);
    
    # Check admin permission
    if ( !check_admin_permission($user) ) {
        return json_error(403, "Access denied. Admin privileges required.");
    }
    
    # Read request body
    my $body = $request->content;
    if ( !$body ) {
        return json_error(400, "Request body is required");
    }
    
    # Parse JSON
    my $json = JSON->new->utf8;
    my $data;
    eval {
        $data = $json->decode($body);
    };
    if ( $@ ) {
        return json_error(400, "Invalid JSON: $@");
    }
    
    # Read current config
    my ($readErr, $currentConfig) = $bpc->ConfigDataRead();
    if ( defined($readErr) ) {
        return json_error(500, "Failed to read current config: $readErr");
    }
    
    # Update email settings
    $currentConfig->{EMailFromUserName} = $data->{emailFrom} if ( defined($data->{emailFrom}) );
    $currentConfig->{EMailAdminUserName} = $data->{emailTo} if ( defined($data->{emailTo}) );
    $currentConfig->{EMailAdminSubject} = $data->{emailSubject} if ( defined($data->{emailSubject}) );
    $currentConfig->{EMailNoBackupRecentMesg} = $data->{emailBody} if ( defined($data->{emailBody}) );
    if ( defined($data->{sendReminders}) ) {
        $currentConfig->{EMailNotifyMinDays} = $data->{sendReminders} ? 2.5 : 0;
    }
    
    # Write config
    my $writeErr = $bpc->ConfigDataWrite(undef, $currentConfig);
    if ( defined($writeErr) ) {
        return json_error(500, $writeErr);
    }
    
    # Reload server
    server_connect();
    if ( $bpc->ServerOK() ) {
        $bpc->ServerMesg("server reload");
    }
    
    return json_success({ success => 1, message => "Notification settings saved successfully" });
}

sub json_error1 {
    my ($msg, $code) = @_;
    $code ||= 400;
    my $body = encode_json({ error => $msg // '' });

    return [
        $code,
        [ 'Content-Type' => 'application/json' ],
        [ $body ]
    ];
}

sub json_response {
    my ($data, $code) = @_;
    $code ||= 200;
    my $body = encode_json($data);

    return [
        $code,
        [ 'Content-Type' => 'application/json' ],
        [ $body ]
    ];
}


sub init_backuppc1 {
    # ensure caller can override
    $ENV{BACKUPPC_CONF_DIR} ||= '/etc/BackupPC';

    # If already initialized, check for config reload
    if (defined $bpc) {
        eval {                                   # guard in case methods die
            if (defined $bpc->can('ConfigMTime') && $bpc->ConfigMTime() != $ConfigMTime) {
                $bpc->ConfigRead();
                $ConfigMTime = $bpc->ConfigMTime();
                umask($bpc->Conf()->{UmaskMode}) if $bpc->can('Conf');
            }
        };
        return $bpc;
    }

    # Not initialized yet — create object
    eval {
        # BackupPC::Lib->new accepts config dir as first arg in many installs
        $bpc = BackupPC::Lib->new($ENV{BACKUPPC_CONF_DIR});
    };
    if ($@) {
        # creation threw an exception
        $bpc = undef;
        return undef;
    }

    unless (defined $bpc) {
        return undef;
    }

    # Populate config mtime & umask if available
    eval {
        $ConfigMTime = $bpc->ConfigMTime() if $bpc->can('ConfigMTime');
        umask($bpc->Conf()->{UmaskMode}) if $bpc->can('Conf') && ref $bpc->Conf();
    };

    return $bpc;
}


# POST /api/restore/:hostname/backups/:backupNum/requests
# Append fileList to latest RestoreInfo.<id>

sub handle_post_append_restore_files {
    my ($env) = @_;
    my $request = Plack::Request->new($env);

    # -------------------------------------------------------
    # CORS: Preflight OPTIONS request
    # -------------------------------------------------------
    if ($request->method eq 'OPTIONS') {
        my $res = $request->new_response(200);
        $res->headers->set("Access-Control-Allow-Origin"  => "*");
        $res->headers->set("Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS");
        $res->headers->set("Access-Control-Allow-Headers" => "Content-Type");
        return $res->finalize;
    }

    # -------------------------------------------------------
    # Helper: add CORS headers to final JSON PSGI response
    # -------------------------------------------------------
    my $add_cors = sub {
        my ($psgi) = @_;
        my ($status, $headers, $body) = @$psgi;

        push @$headers,
            "Access-Control-Allow-Origin"  => "*",
            "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers" => "Content-Type";

        return $psgi;
    };

    # Initialize BackupPC
    init_backuppc1();
    our $bpc;
    return $add_cors->(json_error1("BackupPC not initialized", 500)) unless $bpc;

    # Extract path params
    my %params = extract_path_params(
        $request->path_info,
        '/api/restore/:hostname/backups/:backupNum/requests'
    );

    my $host      = $params{hostname};
    my $backupNum = $params{backupNum};

    # Read JSON body
    my $raw_json = $request->content;
    my $data;
    eval { $data = JSON::PP->new->utf8->decode($raw_json); };
    return $add_cors->(json_error1("Invalid JSON: $@", 400)) if $@;

    my @newFiles = @{ $data->{files} || [] };
    return $add_cors->(json_error1("No files provided", 400)) unless @newFiles;

    # Read share
    my $share = $data->{share} || 'sharedforsudheer';

    # BackupPC directories
    my $TopDir    = $bpc->TopDir();
    my $hostDir   = "$TopDir/pc/$host";
    my $backupDir = "$hostDir/$backupNum";

    return $add_cors->(json_error1("Host directory not found: $hostDir", 404)) unless -d $hostDir;
    return $add_cors->(json_error1("Backup directory not found: $backupDir", 404)) unless -d $backupDir;

    # Find latest RestoreInfo.<id>
    opendir(my $dh, $hostDir) or return $add_cors->(json_error1("Cannot open $hostDir: $!", 500));
    my @files = grep { /^RestoreInfo\.(\d+)$/ } readdir($dh);
    closedir($dh);

    my $latest_id = @files ? (sort { $b <=> $a } map { /RestoreInfo\.(\d+)/; $1 } @files)[0] : 1;
    my $latest = "RestoreInfo.$latest_id";
    my $restoreFile = "$hostDir/$latest";

    # Read or initialize RestoreInfo
    my @lines;
    if (-e $restoreFile) {
        open my $fh, '<', $restoreFile or return $add_cors->(json_error1("Cannot open $restoreFile: $!", 500));
        my @orig_lines = <$fh>;
        close $fh;

        my $in_restore_req = 0;
        for my $line (@orig_lines) {
            if ($line =~ /^\s*%RestoreReq\s*=\s*\(/) {
                $in_restore_req = 1;
                push @lines, "%RestoreReq = (\n";
                next;
            }
            if ($in_restore_req) {
                if ($line =~ /\);\s*$/) {
                    $in_restore_req = 0;
                    push @lines, ");\n";
                }
                next;
            }
            push @lines, $line unless $in_restore_req;
        }
    } else {
        @lines = ("# Created by API\n", "%RestoreReq = (\n", ");\n");
    }

    # Insert new RestoreReq
    my $user = 'backuppc';
    my $reqTime = time();
    my $files_text = join(",\n    ", map { "'$_'" } @newFiles);

    for my $i (0..$#lines) {
        if ($lines[$i] =~ /^\s*\);\s*$/) {
            my $restore_req_text = <<"EOF";
  'fileList' => [
    $files_text
  ],
  'hostDest' => '$host',
  'hostSrc' => '$host',
  'num' => '$backupNum',
  'pathHdrDest' => '/',
  'pathHdrSrc' => '/',
  'reqTime' => $reqTime,
  'shareDest' => '$share',
  'shareSrc' => '$share',
  'user' => '$user'
EOF
            $lines[$i] = $restore_req_text . "\n);\n";
            last;
        }
    }

    # Write back RestoreInfo
    open my $fh_out, '>', $restoreFile or return $add_cors->(json_error1("Cannot write $restoreFile: $!", 500));
    print $fh_out @lines;
    close $fh_out;

    # SUCCESS response with CORS
    return $add_cors->(json_response({
        message     => "Files appended successfully",
        restoreInfo => $latest,
        addedFiles  => \@newFiles,
        share       => $share,
    }));
}

# POST /api/login - Verify user
sub handle_post_login {
    my ($env) = @_;
    my $request = Plack::Request->new($env);
      # CORS: Preflight OPTIONS request
    # -------------------------------------------------------
    if ($request->method eq 'OPTIONS') {
        my $res = $request->new_response(200);
        $res->headers->set("Access-Control-Allow-Origin"  => "*");
        $res->headers->set("Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS");
        $res->headers->set("Access-Control-Allow-Headers" => "Content-Type");
        return $res->finalize;
    }

    # -------------------------------------------------------
    # Helper: add CORS headers to final JSON PSGI response
    # -------------------------------------------------------
    my $add_cors = sub {
        my ($psgi) = @_;
        my ($status, $headers, $body) = @$psgi;

        push @$headers,
            "Access-Control-Allow-Origin"  => "*",
            "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers" => "Content-Type";

        return $psgi;
    };


    my $json_file = "/home/aagarwalAnubhav/users.json";

    # Read file
    open(my $fh, '<', $json_file) or return $add_cors->(json_error1("Cannot open JSON file", 500));
    local $/;
    my $data = <$fh>;
    close($fh);

    my $users = decode_json($data)->{users};

    # Get JSON from UI
    my $body = $request->content;
    my $input;
    eval { $input = decode_json($body); };
    return $add_cors->(json_error1("Invalid JSON input", 400)) if $@;

    my $userid = $input->{userid};
    my $password = $input->{password};

    # Validate missing fields
    return $add_cors->(json_error1("Missing userid or password", 400))
        if (!$userid || !$password);

    # Search user
    foreach my $u (@$users) {
        if ($u->{userid} eq $userid && $u->{password} eq $password) {
            return $add_cors->(json_response({
                status => "success",
                role   => $u->{role},
                user   => $u->{userid}
            }));
        }
    }

    return $add_cors->(json_error1("Invalid userid or password", 401));
}

# POST /api/get-user-hosts
sub handle_post_get_user_hosts {
    my ($env) = @_;
    my $req = Plack::Request->new($env);
      # CORS: Preflight OPTIONS request
    # -------------------------------------------------------
    if ($req->method eq 'OPTIONS') {
        my $res = $req->new_response(200);
        $res->headers->set("Access-Control-Allow-Origin"  => "*");
        $res->headers->set("Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS");
        $res->headers->set("Access-Control-Allow-Headers" => "Content-Type");
        return $res->finalize;
    }

    # -------------------------------------------------------
    # Helper: add CORS headers to final JSON PSGI response
    # -------------------------------------------------------
    my $add_cors = sub {
        my ($psgi) = @_;
        my ($status, $headers, $body) = @$psgi;

        push @$headers,
            "Access-Control-Allow-Origin"  => "*",
            "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers" => "Content-Type";

        return $psgi;
    };
    # Read POST JSON
    my $body  = $req->content;
    my $input = eval { decode_json($body) };
    return $add_cors->(json_error1("Invalid JSON", 400)) if $@;

    my $userid = $input->{userid} || "";
    return $add_cors->(json_error1("userid is required", 400)) if $userid eq "";

    # Read users.json
    my $file = "/home/aagarwalAnubhav/users.json";
    open my $fh, "<", $file or return $add_cors->(json_error1("Cannot open users.json", 500));
    local $/;
    my $json_text = <$fh>;
    close $fh;

    my $data = eval { decode_json($json_text) };
    return $add_cors->(json_error1("Invalid users.json format", 500)) if $@;

    my ($role, $hostString);
    my @hosts = ();

    # Find user record
    foreach my $u (@{$data->{users}}) {
        if ($u->{userid} eq $userid) {
            $role       = $u->{role} // "";
            $hostString = $u->{host} // "";
            last;
        }
    }

    # -------------------------
    # ADMIN → RETURN ALL HOSTS
    # -------------------------
    #if (defined $role && $role eq 'Admin') {
        # Directly call your GET API method that returns all hosts
       # return handle_get_hosts($env);
   # }

    # -------------------------
    # NORMAL USER → limited hosts
    # -------------------------
    if ($hostString ne "") {
        @hosts = split /\s*,\s*/, $hostString;
    }

    #my $response = {
      #  userid => $userid,
      #  hosts  => \@hosts
  #  };
     return $add_cors->(json_response({
                userid => $userid,
                hosts  => \@hosts
            }));

}

sub handle_get_global_config {
    return json_success({}) unless -f $GLOBAL_CONFIG_FILE;

    open my $fh, '<', $GLOBAL_CONFIG_FILE
        or return json_error(500, "Cannot read global config");

    local $/;
    my $data = decode_json(<$fh>);
    close $fh;

    return json_success($data);
}



# Main PSGI application
sub app {
    my $env = shift;
    my $request = Plack::Request->new($env);
    my $path = $request->path_info;
    my $method = $request->method;
    
    # Handle OPTIONS for CORS preflight
    if ( $method eq 'OPTIONS' ) {
        my $response = Plack::Response->new(200);
        add_cors_headers($response);
        return $response->finalize;
    }
    
    # Route requests
    my $result;
    
    # Config endpoints
    if ( $path eq '/api/config' && $method eq 'GET' ) {
        $result = handle_get_config($env);
    }
    elsif ( $path eq '/api/config' && $method eq 'PUT' ) {
        $result = handle_put_config($env);
    }
    # Hosts endpoints
    elsif ( $path eq '/api/hosts' && $method eq 'GET' ) {
        $result = handle_get_hosts($env);
    }
    elsif ( $path =~ /^\/api\/hosts\/([^\/]+)$/ && $method eq 'GET' ) {
        $result = handle_get_host($env);
    }
    elsif ( $path eq '/api/hosts' && $method eq 'POST' ) {
        $result = handle_post_hosts($env);
    }
    elsif ( $path =~ /^\/api\/hosts\/([^\/]+)$/ && $method eq 'PUT' ) {
        $result = handle_put_host($env);
    }
    elsif ( $path =~ /^\/api\/hosts\/([^\/]+)$/ && $method eq 'DELETE' ) {
        $result = handle_delete_host($env);
    }
    # Backups endpoints
    elsif ( $path eq '/api/backups' && $method eq 'GET' ) {
        $result = handle_get_backups($env);
    }
    elsif ( $path =~ /^\/api\/backups\/([^\/]+)\/trigger$/ && $method eq 'POST' ) {
        $result = handle_post_backup_trigger($env);
    }
    # Restore endpoints
    elsif ( $path =~ /^\/api\/restore\/([^\/]+)\/backups$/ && $method eq 'GET' ) {
        $result = handle_get_restore_backups($env);
    }
    elsif ( $path =~ /^\/api\/restore\/([^\/]+)\/backups\/([^\/]+)\/files$/ && $method eq 'GET' ) {
        $result = handle_get_restore_files($env);
    }
    elsif ( $path =~ /^\/api\/restore\/([^\/]+)\/backups\/([^\/]+)\/restore$/ && $method eq 'POST' ) {
        $result = handle_post_restore($env);
    }
    # Reports endpoints
    elsif ( $path eq '/api/reports/log-types' && $method eq 'GET' ) {
        $result = handle_get_log_types($env);
    }
    elsif ( $path =~ /^\/api\/reports\/logs\/([^\/]+)\/dates$/ && $method eq 'GET' ) {
        $result = handle_get_log_dates($env);
    }
    elsif ( $path =~ /^\/api\/reports\/logs\/([^\/]+)\/([^\/]+)$/ && $method eq 'GET' && $path !~ /\/dates$/) {
        $result = handle_get_log_content($env);
    }
    # Notifications endpoints
    elsif ( $path eq '/api/notifications' && $method eq 'GET' ) {
        $result = handle_get_notifications($env);
    }
    elsif ( $path eq '/api/notifications' && $method eq 'PUT' ) {
        $result = handle_put_notifications($env);
    }    
    elsif ($path =~ m|^/api/restore/[^/]+/backups/\d+/requests$| && $method eq 'POST') {
       $result = handle_post_append_restore_files($env);
   }
   # Login route
  elsif ($path eq '/api/login' && $request->method eq 'POST') {
    return handle_post_login($env);
  }
  elsif ($path eq '/api/get-user-hosts' && $request->method eq 'POST') {
     return handle_post_get_user_hosts($env);
  }
    # elsif ( $path eq '/api/global-config' && $method eq 'POST' ) {
    # $result = handle_post_global_config($env);
    # }
    elsif ( $path =~ m|^/api/global-config/?$| && $method eq 'POST' ) {
    $result = handle_post_global_config($env);
    }
    elsif ( $path =~ m|^/api/global-config/?$| && $method eq 'GET' ) {
    $result = handle_get_global_config($env);
    }


    else {
        my $json = JSON->new->utf8->pretty;
        my $response = Plack::Response->new(404);
        $response->content_type('application/json');
        $response->body($json->encode({ error => "Not found" }));
        add_cors_headers($response);
        $result = $response->finalize;
    }
    
    return $result;
}


# Run the application
return \&app;

