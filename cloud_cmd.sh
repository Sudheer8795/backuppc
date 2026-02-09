#!/bin/bash
 
echo "Starting all services..."
 
perl runcommand.pl &
perl cloud_settings.pl &
 
plackup -p 5003 -o 0.0.0.0 getSchedule.psgi &
plackup -p 8091 getCloudTransfer.psgi &
plackup -p 8092 -o 0.0.0.0 transferPolicies.psgi &
plackup -p 8093 -o 0.0.0.0 cloudTransfer.psgi &
 
plackup -s HTTP::Server::PSGI -o 0.0.0.0 -p 8095 delete_log.psgi &
plackup -p 8096 -o 0.0.0.0 cloud_overview.psgi &
 
perl readlog.pl daemon -l http://*:3000 &
 
plackup -s HTTP::Server::PSGI -o 0.0.0.0 -p 8090 app.psgi &
 
perl logWrite.pl &
 
echo "All services started."
wait
