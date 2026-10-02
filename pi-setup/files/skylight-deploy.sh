#!/bin/bash
# Run by cron every 2 min. Pulls skylight from GitHub; reinstalls deps only when they changed.
cd /home/pi/skylight || exit 1
before=$(git rev-parse HEAD)
git pull --ff-only origin main >> /home/pi/skylight-deploy.log 2>&1 || exit 1
after=$(git rev-parse HEAD)
if [ "$before" != "$after" ] && git diff --name-only "$before" "$after" | grep -qE '^package(-lock)?\.json$'; then
  npm install --silent >> /home/pi/skylight-deploy.log 2>&1
fi
