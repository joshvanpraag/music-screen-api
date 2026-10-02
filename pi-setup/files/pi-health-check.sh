#!/bin/bash
# Run by cron every 5 min. Logs throttling/undervoltage flags and temperature.
echo "$(date +%Y-%m-%d\ %H:%M:%S) $(vcgencmd get_throttled) $(vcgencmd measure_temp)" >> /home/pi/pi-health.log
