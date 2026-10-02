#!/bin/bash
# Run from your PC (Git Bash), not the Pi. Copies the files that git can't hold
# (they contain keys) into ~/sonos-display-backup/. Re-run after changing any of them.
#
#   bash pi-setup/backup-from-pi.sh
#
# To restore onto a rebuilt Pi, see "Restoring from backup" in pi-setup/README.md.

set -euo pipefail

PI="${PI:-pi@sonos-display.local}"
DEST="$HOME/sonos-display-backup"
mkdir -p "$DEST"

for f in \
  music-screen-api/sonos_settings.py \
  skylight/immich-settings.json \
  skylight/prompts.json; do
  mkdir -p "$DEST/$(dirname "$f")"
  if scp -q "$PI:$f" "$DEST/$f"; then echo "saved  $f"; else echo "MISSING $f"; fi
done

echo "Backup in $DEST ($(date +%Y-%m-%d))"
