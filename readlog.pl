#!/usr/bin/env perl
use Mojolicious::Lite;

# Enable CORS for all routes
under sub {
  my $c = shift;
  $c->res->headers->header('Access-Control-Allow-Origin' => '*');
  $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
  $c->res->headers->header('Access-Control-Allow-Headers' => 'Content-Type');
  return 1;
};

# Handle preflight OPTIONS requests
options '/readlog' => sub {
  my $c = shift;
  $c->render(text => '', status => 200);
};

get '/readlog' => sub {
  my $c = shift;
  my $path = '/home/aagarwalAnubhav/rcloneLog.txt';

  open my $fh, '<', $path or return $c->render(text => "Can't open file: $!");
  my $content = do { local $/; <$fh> };
  close $fh;

  $c->render(text => $content);
};

app->start;

