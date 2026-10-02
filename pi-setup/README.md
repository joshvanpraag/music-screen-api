# Rebuilding the Sonos display Pi

This folder rebuilds the kitchen album-art display from a blank SD card. It exists only in
`joshvanpraag/music-screen-api`, our fork. It isn't meant for upstream.

**Hardware:** Raspberry Pi 3 A+ with a Pimoroni HyperPixel 4.0 Square (non-touch, 720×720).
**What runs on it:**
- `node-sonos-http-api` ([our fork](https://github.com/joshvanpraag/node-sonos-http-api)) on port 5005 reports what the Kitchen speaker is playing.
- `music-screen-api` (this repo) draws the album art full-screen.
- Optional: the `skylight` dashboard (private repo) on port 3000.

## Rebuild in 4 steps

**1. Flash the SD card** with [Raspberry Pi Imager](https://www.raspberrypi.com/software/):
- Device: Raspberry Pi 3. OS: **Raspberry Pi OS (32-bit), Bookworm, with desktop**. If Imager now
  lists Bookworm under "Raspberry Pi OS (other)" or "Legacy", pick it from there; newer releases are untested.
- Edit settings (the gear / "Customise" step):
  - Hostname: `sonos-display`
  - Username: `pi`, plus a password you'll remember
  - Wi-Fi: the same network as the Kitchen speaker
  - Services tab: **enable SSH** with password authentication

**2. Boot the Pi and SSH in** from your PC: `ssh pi@sonos-display.local`.
The screen stays black until step 4. That's expected.
If you get a "host key changed" warning, run `ssh-keygen -R sonos-display.local` and try again.

**3. Run the setup script:**
```bash
git clone https://github.com/joshvanpraag/music-screen-api ~/music-screen-api
bash ~/music-screen-api/pi-setup/setup.sh --with-skylight   # leave off --with-skylight to skip the dashboard
```
It asks for the Spotify client ID and secret. They're in `~/sonos-display-backup/` on your PC
(see [Backups](#backups)), or you can create new ones at https://developer.spotify.com/dashboard.
To restore the skylight settings, see [Restoring from backup](#restoring-from-backup) before running it.

**4. Reboot** with `sudo reboot`. After about a minute the album art should appear. To check:
```bash
curl -s localhost:5005/zones | grep -o '"roomName":"[^"]*"' | sort -u
```
You should see Kitchen, Mia's Room, Office and Parent's Room, and **not** Sonos Roam SL.

The script is safe to re-run. If something fails partway, fix it and run it again.

## Backups

Three files can't go in git because they hold keys:

| File | Holds |
|---|---|
| `~/music-screen-api/sonos_settings.py` | Spotify client ID and secret |
| `~/skylight/immich-settings.json` | skylight's Immich settings |
| `~/skylight/prompts.json` | skylight's prompts |

From your PC (Git Bash), in this repo, run:
```bash
bash pi-setup/backup-from-pi.sh
```
It copies them into `~/sonos-display-backup/`. Re-run it whenever you change one of them.

### Restoring from backup
Between steps 2 and 3, copy the backup to the Pi from your PC:
```bash
scp -r ~/sonos-display-backup pi@sonos-display.local:/tmp/backup
```
Then on the Pi, use these in place of step 3:
```bash
git clone https://github.com/joshvanpraag/music-screen-api ~/music-screen-api
cp /tmp/backup/music-screen-api/sonos_settings.py ~/music-screen-api/
bash ~/music-screen-api/pi-setup/setup.sh --with-skylight
cp /tmp/backup/skylight/*.json ~/skylight/ && pm2 restart skylight
```
The script won't ask for Spotify keys when `sonos_settings.py` is already there.

## What the script sets up, and why

Each of these fixes a problem we actually hit. If you set the Pi up by hand, don't skip any of them.

| Setting | Why |
|---|---|
| `"household"` in `node-sonos-http-api/settings.json` | The API locks onto whichever speaker answers first. The Roam SL is a separate S2 system on the same Wi-Fi; when it answered first, Kitchen vanished and the art froze. `find-household.js` looks up Kitchen's household ID automatically. |
| `"webhook": "http://localhost:8080/"` | How the API tells the display the track changed. |
| HyperPixel overlay in `/boot/firmware/config.txt` | `dtoverlay=vc4-kms-dpi-hyperpixel4sq` plus `display_auto_detect=0`. Without the second line the screen stays black. Don't use Pimoroni's installer script. |
| Autostart in `~/.config/labwc/autostart` | Bookworm uses labwc. The LXDE autostart path in the Hackster guide is never read. The 45s delayed `/reindex` gives slow S1 speakers time to wake up. |
| pm2 restart every 30 min (cron) | Speakers can drop out of discovery after long idle periods; a restart finds them again. It must use the full path `/usr/local/bin/pm2`: cron can't find plain `pm2`, and for months the restart silently never ran. |
| Log caps (`pm2-logrotate` and `/etc/logrotate.d/pi-home-logs`) | While Kitchen was missing, the API logged an error on every poll, and one log reached 1.6 GB. Every log is now capped at 5 MB × 3 copies. |
| Wi-Fi power-save off | With power-save on, the Pi 3 A+ Wi-Fi drops off the network until it's power-cycled. |
| Persistent journal | Keeps system logs across reboots so crashes can be diagnosed. |
| Disabled cups, bluetooth, ModemManager, colord, PipeWire | The Pi has only 425 MB of RAM. None of these are used: audio plays through the Sonos speakers, not the Pi. |
| SSH key from `files/authorized_keys` | Lets Claude Code on Josh's PC (`~/.ssh/id_ed25519_sonos`) SSH in without a password. |
| `pi-health-check.sh` (cron, every 5 min) | Logs undervoltage/throttling and temperature to `~/pi-health.log` for diagnosing hangs. |

Only install Node from apt (`nodejs npm`, Node 18). NodeSource doesn't support this Pi's 32-bit OS.

## When the album art is stuck

1. Check the API sees the speakers: `curl -s http://sonos-display.local:5005/zones` should list Kitchen.
2. If it doesn't: `ssh pi@sonos-display.local 'pm2 restart sonos-http-api'`, then wait 30s and check again.
3. Still missing? Run `node ~/music-screen-api/pi-setup/find-household.js Kitchen --all` on the Pi.
   It lists every speaker with its household ID. If Kitchen's ID changed (for example after a
   Sonos factory reset), re-run `setup.sh`, which rewrites `settings.json` with the new ID.
4. Display logs: `~/music-screen-api.log`. API logs: `pm2 logs sonos-http-api`.

## Known limitations

- The HyperPixel backlight can't be turned off on Bookworm (GPIO error), so the screen stays on.
- SiriusXM DJ announcements show the channel logo, because Spotify has no matching art.
- The desktop flashes briefly on boot before the display starts.
