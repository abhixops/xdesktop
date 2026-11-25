# Init hooks and autostart

xdesktop has two extension points:

| Hook | Runs as | When |
|---|---|---|
| `/etc/xdesktop/init.d/*.sh` | root | Every start, in sorted order, before the desktop starts |
| `~/.xdesktop/autostart.sh` (must be executable) | desktop user | Every start, in the background, after XFCE is up |

## Files

- [`init.d/10-example.sh`](init.d/10-example.sh): sample root hook. It logs a
  line, shows an optional package install, and copies the sample autostart
  script into the user's home if none exists.
- [`autostart.sh`](autostart.sh): sample user script. It appends to
  `~/.xdesktop/autostart.log` and has commented-out examples for opening a
  terminal or VS Code.
- [`compose.override.yml`](compose.override.yml): mounts both files.

## Usage

```bash
docker compose -f docker-compose.yml -f examples/init-hooks/compose.override.yml up -d
docker compose logs xdesktop | grep 10-example
```

Hooks are mounted one file at a time, so hooks already in the image are not
hidden. To add your own, mount more files into `/etc/xdesktop/init.d/`.

Home is a persistent volume, so you can also edit the autostart script directly
inside the desktop (`~/.xdesktop/autostart.sh`). Remember `chmod +x`.
