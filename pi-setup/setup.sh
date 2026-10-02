#!/bin/bash
# Rebuilds the Sonos album-art display Pi from a fresh Raspberry Pi OS (Bookworm) install.
# Safe to re-run: every step checks before changing anything.
#
#   git clone https://github.com/joshvanpraag/music-screen-api ~/music-screen-api
#   bash ~/music-screen-api/pi-setup/setup.sh                 # display only
#   bash ~/music-screen-api/pi-setup/setup.sh --with-skylight # display + skylight dashboard
#
# Never prompts, so it can run over SSH. Secrets come from ~/sonos-display-backup/
# (copied over by the rebuild runbook), or SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET env vars.
#
# Exit codes: 0 done, 2 secrets missing, 3 skylight needs a GitHub deploy key (see README).
# See pi-setup/README.md for the why behind each step.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ROOM="Kitchen"
HOME_DIR="/home/pi"
SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SETUP_DIR/files"
SONOS_API_DIR="$HOME_DIR/node-sonos-http-api"
DISPLAY_DIR="$HOME_DIR/music-screen-api"
SKYLIGHT_DIR="$HOME_DIR/skylight"
BACKUP_DIR="$HOME_DIR/sonos-display-backup"
PM2=/usr/local/bin/pm2
WITH_SKYLIGHT=false
[[ "${1:-}" == "--with-skylight" ]] && WITH_SKYLIGHT=true

step() { echo; echo "==> $*"; }

if [[ "$(whoami)" != "pi" ]]; then
  echo "Run this as the 'pi' user (not root, not sudo)."; exit 1
fi

step "Installing system packages"
sudo apt-get update -q
sudo apt-get install -y -q git curl nodejs npm python3-pip python3-tk python3-pil python3-pil.imagetk unclutter

step "Installing Python packages"
pip3 install -q --break-system-packages -r "$DISPLAY_DIR/requirements.txt" spotipy

step "Installing pm2"
[[ -x "$PM2" ]] || sudo npm install -g pm2

step "Cloning node-sonos-http-api (our fork)"
if [[ ! -d "$SONOS_API_DIR/.git" ]]; then
  git clone https://github.com/joshvanpraag/node-sonos-http-api "$SONOS_API_DIR"
fi
(cd "$SONOS_API_DIR" && npm install --omit=dev --no-audit --no-fund)

step "Writing node-sonos-http-api/settings.json (locks to the $ROOM household, ignores the Roam)"
HOUSEHOLD="$(node "$SETUP_DIR/find-household.js" "$ROOM" || true)"
if [[ -z "$HOUSEHOLD" ]]; then
  HOUSEHOLD="Sonos_Azfow5K3VwydSf8ywhWNZSsDFM"
  echo "Could not find $ROOM on the network; using last known household $HOUSEHOLD"
fi
cat > "$SONOS_API_DIR/settings.json" <<EOF
{
  "webhook": "http://localhost:8080/",
  "household": "$HOUSEHOLD"
}
EOF
cat "$SONOS_API_DIR/settings.json"

step "Writing music-screen-api/sonos_settings.py"
if [[ -f "$DISPLAY_DIR/sonos_settings.py" ]]; then
  echo "Already exists, leaving it alone."
elif [[ -f "$BACKUP_DIR/music-screen-api/sonos_settings.py" ]]; then
  cp "$BACKUP_DIR/music-screen-api/sonos_settings.py" "$DISPLAY_DIR/sonos_settings.py"
  echo "Restored from $BACKUP_DIR."
else
  if [[ -z "${SPOTIFY_CLIENT_ID:-}" || -z "${SPOTIFY_CLIENT_SECRET:-}" ]]; then
    echo "!! No sonos_settings.py, no backup in $BACKUP_DIR, and no SPOTIFY_CLIENT_ID/SECRET env vars."
    exit 2
  fi
  sed -e "s|__SPOTIFY_CLIENT_ID__|$SPOTIFY_CLIENT_ID|" \
      -e "s|__SPOTIFY_CLIENT_SECRET__|$SPOTIFY_CLIENT_SECRET|" \
      "$FILES/sonos_settings.py.template" > "$DISPLAY_DIR/sonos_settings.py"
fi

step "Configuring the HyperPixel 4.0 Square screen (/boot/firmware/config.txt)"
BOOT=/boot/firmware/config.txt
sudo sed -i 's/^display_auto_detect=1/display_auto_detect=0/' "$BOOT"
grep -q '^dtoverlay=vc4-kms-dpi-hyperpixel4sq' "$BOOT" || echo 'dtoverlay=vc4-kms-dpi-hyperpixel4sq' | sudo tee -a "$BOOT" >/dev/null

step "Autostarting the display (labwc, not LXDE)"
mkdir -p "$HOME_DIR/.config/labwc"
cp "$FILES/labwc-autostart" "$HOME_DIR/.config/labwc/autostart"

step "Starting node-sonos-http-api under pm2"
"$PM2" describe sonos-http-api >/dev/null 2>&1 || \
  "$PM2" start "$SONOS_API_DIR/server.js" --name sonos-http-api --cwd "$SONOS_API_DIR"

step "Capping pm2 logs (pm2-logrotate: 5 MB x 3)"
"$PM2" describe pm2-logrotate >/dev/null 2>&1 || "$PM2" install pm2-logrotate
"$PM2" set pm2-logrotate:max_size 5M >/dev/null
"$PM2" set pm2-logrotate:retain 3 >/dev/null
"$PM2" set pm2-logrotate:compress true >/dev/null
"$PM2" set pm2-logrotate:workerInterval 60 >/dev/null

if $WITH_SKYLIGHT; then
  step "Setting up skylight dashboard (port 3000)"
  if [[ ! -d "$SKYLIGHT_DIR/.git" ]]; then
    # Private repo: the Pi needs its own SSH key added as a deploy key on GitHub.
    [[ -f "$HOME_DIR/.ssh/id_ed25519" ]] || ssh-keygen -t ed25519 -N "" -C "pi@sonos-display" -f "$HOME_DIR/.ssh/id_ed25519" -q
    if ! GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
         git clone git@github.com:joshvanpraag/vanpraagskylight.git "$SKYLIGHT_DIR"; then
      echo
      echo "!! GitHub refused the clone. Add this key as a read-only deploy key on"
      echo "!! joshvanpraag/vanpraagskylight (README: 'skylight deploy key'), then re-run:"
      echo
      cat "$HOME_DIR/.ssh/id_ed25519.pub"
      exit 3
    fi
  fi
  (cd "$SKYLIGHT_DIR" && npm install --no-audit --no-fund)
  for f in immich-settings.json prompts.json; do
    if [[ ! -f "$SKYLIGHT_DIR/$f" && -f "$BACKUP_DIR/skylight/$f" ]]; then
      cp "$BACKUP_DIR/skylight/$f" "$SKYLIGHT_DIR/$f" && echo "Restored $f from $BACKUP_DIR."
    fi
    [[ -f "$SKYLIGHT_DIR/$f" ]] || echo "!! $SKYLIGHT_DIR/$f is missing (gitignored, not in backup)."
  done
  install -m 755 "$FILES/skylight-deploy.sh" "$HOME_DIR/skylight-deploy.sh"
  "$PM2" describe skylight >/dev/null 2>&1 || \
    "$PM2" start "$SKYLIGHT_DIR/server.js" --name skylight --cwd "$SKYLIGHT_DIR"
fi

step "Starting pm2 on boot"
"$PM2" save
sudo env PATH="$PATH:/usr/bin" "$PM2" startup systemd -u pi --hp "$HOME_DIR" >/dev/null

step "Installing cron jobs"
install -m 755 "$FILES/pi-health-check.sh" "$HOME_DIR/pi-health-check.sh"
{
  echo "# Managed by music-screen-api/pi-setup/setup.sh. Use the full pm2 path: cron's PATH lacks /usr/local/bin."
  echo "*/30 * * * * $PM2 restart sonos-http-api > /dev/null 2>&1"
  echo "*/5 * * * * $HOME_DIR/pi-health-check.sh"
  if $WITH_SKYLIGHT; then echo "*/2 * * * * $HOME_DIR/skylight-deploy.sh"; fi
} | crontab -
crontab -l

step "Capping ~/*.log files (logrotate: 5 MB x 3)"
sudo install -m 644 "$FILES/logrotate-pi-home-logs" /etc/logrotate.d/pi-home-logs

step "Pi stability fixes"
# Wi-Fi power-save makes the Pi 3 A+ drop off the network until power-cycled.
sudo install -m 644 "$FILES/wifi-powersave-off.conf" /etc/NetworkManager/conf.d/wifi-powersave-off.conf
# Keep logs across reboots so crashes can be diagnosed.
sudo sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
# Free RAM (only 425 MB): nothing here prints, pairs Bluetooth, or plays audio locally.
for s in cups cups-browsed ModemManager colord bluetooth rtkit-daemon; do
  sudo systemctl disable --now "$s" >/dev/null 2>&1 || true
done
for s in pipewire pipewire-pulse wireplumber pipewire.socket pipewire-pulse.socket; do
  sudo systemctl --global mask "$s" >/dev/null 2>&1 || true
done

step "Allowing SSH from Josh's PC (key in pi-setup/files/authorized_keys)"
mkdir -p "$HOME_DIR/.ssh" && chmod 700 "$HOME_DIR/.ssh"
touch "$HOME_DIR/.ssh/authorized_keys" && chmod 600 "$HOME_DIR/.ssh/authorized_keys"
grep -qxF "$(cat "$FILES/authorized_keys")" "$HOME_DIR/.ssh/authorized_keys" || \
  cat "$FILES/authorized_keys" >> "$HOME_DIR/.ssh/authorized_keys"

step "Done"
echo "Reboot to start everything: sudo reboot"
echo "After about a minute, check: curl -s localhost:5005/zones | grep -o '\"roomName\":\"[^\"]*\"' | sort -u"
