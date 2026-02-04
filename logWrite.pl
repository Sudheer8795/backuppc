#!/usr/bin/env perl
use strict;
use warnings;
use Mojolicious::Lite;
use POSIX qw(strftime);

my $log_file = "/home/aagarwalAnubhav/rcloneLog.txt";

# Add a before_dispatch hook to set CORS headers
hook before_dispatch => sub {
    my $c = shift;
    $c->res->headers->header('Access-Control-Allow-Origin' => '*');
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
    $c->res->headers->header('Access-Control-Allow-Headers' => 'Content-Type');
};

options '/log' => sub {
    my $c = shift;
    $c->render(text => '', status => 200);
};


post '/log' => sub {
    my $c = shift;
    my $data = $c->req->json || {};
    my $level   = $data->{level}   || 'INFO';
    my $message = $data->{message} || '';
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $entry = "[$timestamp] [$level] $message\n";

    open my $fh, '>>', $log_file or die "Cannot open $log_file: $!";
    print $fh $entry;
    close $fh;

    $c->render(json => { status => "ok", logged => $entry });
};

app->start('daemon', '-l', 'http://*:8085');

