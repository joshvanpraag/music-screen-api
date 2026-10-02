# Rebuilding the Sonos display Pi

This folder rebuilds the kitchen album-art display from a blank SD card. It exists only in
`joshvanpraag/music-screen-api`, our fork. It isn't meant for upstream.

**Hardware:** Raspberry Pi 3 A+ with a Pimoroni HyperPixel 4.0 Square (non-touch, 720×720).
**What runs on it:**
- `node-sonos-http-api` ([our fork](https://github.com/joshvanpraag/node-sonos-http-api)) on port 5005 reports what the Kitchen speaker is playing.
- `music-screen-api` (this repo) draws the album art full-screen.
- Optional: the `skylight` dashboard (private repo) on port 3000.

## If the Pi dies: your part

This takes about 10 minutes. After that, Claude Code does everything else.

**1. Flash a new SD card** with [Raspberry Pi Imager](https://www.raspberrypi.com/software/):
- Device: **Raspberry Pi 3**.
- OS: **Raspberry Pi OS (32-bit), Bookworm, with desktop**. If Imager lists Bookworm under
  "Raspberry Pi OS (other)" or "Legacy", pick it from there. Newer releases are untested.
- In the customisation settings:
  - Hostname: `sonos-display`
  - Username: `pi`, with any password
  - Wi-Fi: the same network as the Kitchen speaker
  - Services: enable SSH, choose **"Allow public-key authentication only"**, and paste this key:
    ```
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGf0I3mDBYzGB6F5yOCqoNbg+Tc4N/fn9ADkEbMHAPwO claude-code@Goblin -> sonos-display
    ```
    This key is what lets Claude log in without your password. The same key is in `files/authorized_keys`.

**2. Put the card in the Pi and power it on.** Wait about 3 minutes for its first boot.
The screen stays black until the end. That's expected.

**3. Tell Claude Code:**
> The Sonos display Pi was replaced and is online. Rebuild it using the runbook in
> music-screen-api/pi-setup/README.md.

## Rebuild runbook (for Claude Code)

Run every step from Josh's Windows PC in Git Bash. **Don't ask Josh for anything.**
Each step is automatic, and the only exceptions are listed in the step itself.

This PC already has what the runbook needs:
- the SSH key `~/.ssh/id_ed25519_sonos` and a `Host sonos-display` entry in `~/.ssh/config`
- the secrets backup in `~/sonos-display-backup/`
- `gh`, logged in as joshvanpraag with `repo` scope

**1. Connect.** The new Pi has a new host key, so clear the old one first:
```bash
ssh-keygen -R sonos-display.local
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes sonos-display 'hostname; grep PRETTY /etc/os-release'
```
- If this fails with `Permission denied (publickey)`, the key wasn't pasted in Imager. Ask Josh to
  re-flash with the key (step 1 above). That's the only fix that needs no password.
- If the host isn't found, wait 2 more minutes, then check that Josh used hostname `sonos-display`.

**2. Copy the secrets backup to the Pi:**
```bash
scp -r ~/sonos-display-backup sonos-display:~/
```

**3. Clone and run setup.** This takes 10–20 minutes on a Pi 3, so run it detached and poll:
```bash
ssh sonos-display 'git clone https://github.com/joshvanpraag/music-screen-api ~/music-screen-api 2>/dev/null || git -C ~/music-screen-api pull --ff-only
  nohup bash -c "bash ~/music-screen-api/pi-setup/setup.sh --with-skylight; echo SETUP_EXIT=\$?" > ~/setup.log 2>&1 &'
ssh sonos-display 'tail -5 ~/setup.log'     # repeat every few minutes until SETUP_EXIT= appears
```

**4. Handle the exit code:**
- `SETUP_EXIT=0`: go to step 5.
- `SETUP_EXIT=3`: skylight is a private repo and the new Pi's key isn't on GitHub yet. Add it, then re-run step 3:
  ```bash
  ssh sonos-display 'cat ~/.ssh/id_ed25519.pub' > /tmp/sonos-pi.pub
  gh repo deploy-key add /tmp/sonos-pi.pub -R joshvanpraag/vanpraagskylight -t "sonos-display $(date +%F)"
  ```
  Afterwards, `gh repo deploy-key list -R joshvanpraag/vanpraagskylight` shows the keys. Delete any
  older `sonos-display` key with `gh repo deploy-key delete <id> -R ...`, since it belonged to the dead Pi.
- `SETUP_EXIT=2`: the secrets backup is missing. This is the only case where you need Josh: ask
  for the Spotify client ID and secret, then re-run with
  `SPOTIFY_CLIENT_ID=... SPOTIFY_CLIENT_SECRET=... bash ~/music-screen-api/pi-setup/setup.sh --with-skylight`.
- Anything else: read `~/setup.log`, fix the cause, and re-run step 3. The script is safe to re-run.

**5. Reboot**, then wait about 2 minutes:
```bash
ssh sonos-display 'sudo reboot'
```

**6. Verify.** All of these must pass:
```bash
ssh sonos-display '
  curl -s localhost:5005/zones | grep -o "\"roomName\":\"[^\"]*\"" | sort -u   # 4 S1 rooms, NOT Sonos Roam SL
  pm2 ls                                                                     # sonos-http-api, skylight, pm2-logrotate online
  curl -s -o /dev/null -w "skylight %{http_code}\n" localhost:3000            # 200
  pgrep -af go_sonos_highres                                                 # display app running
  tail -5 ~/music-screen-api.log; tail -5 ~/autostart.log                    # "New track" if music is playing, no tracebacks
  crontab -l'
```
Then tell Josh it's done, mention anything that failed, and ask him to glance at the screen.

## Backups

Three files can't go in git because they hold keys. The rebuild restores them from
`~/sonos-display-backup/` on Josh's PC:

| File on the Pi | Holds |
|---|---|
| `~/music-screen-api/sonos_settings.py` | Spotify client ID and secret |
| `~/skylight/immich-settings.json` | skylight's Immich settings |
| `~/skylight/prompts.json` | skylight's prompts |

**Re-run the backup after changing any of them.** From the PC, in this repo:
```bash
bash pi-setup/backup-from-pi.sh
```

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
