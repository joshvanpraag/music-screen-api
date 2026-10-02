# Notes for Claude Code

This is Josh's fork of hankhank10/music-screen-api. It runs on the kitchen Sonos display Pi
(`ssh sonos-display`, key auth from this PC). Never push to upstream; only push to `origin`.

- **Pi replaced or rebuilt?** Follow the runbook in [pi-setup/README.md](pi-setup/README.md#rebuild-runbook-for-claude-code)
  end to end, without asking Josh for anything.
- **Album art stuck?** See "When the album art is stuck" in the same README.
- **Changed anything on the Pi** (cron, config, a new setting or file)? Update `pi-setup/` to match
  and push, so a rebuild from git gives the same Pi. If you changed one of the three files
  with secrets in them, run `pi-setup/backup-from-pi.sh` (the README explains why they're not in git).
- Both display repos are public. Never commit secrets: Spotify keys, skylight's json, or the Pi password.
