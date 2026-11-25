# Xdesktop

Xdesktop is an Ubuntu 24.04 XFCE desktop in a Docker container that you use from
your browser through noVNC. It comes with Visual Studio Code, Firefox, Python 3
and the usual terminal tools. It is a lightweight personal "VDI": no VM, just
`docker compose up`.

Image: `ghcr.io/abhixops/xdesktop` · Source: <https://github.com/abhixops/xdesktop>

## Features

- **TigerVNC + noVNC**: the desktop resizes to fit your browser window, and the
  clipboard is shared through the noVNC clipboard panel.
- **HTTPS only by default**: noVNC is served over TLS. It uses a self-signed
  certificate that is generated and renewed automatically, or your own certificate.
- **No default password**: if `VNC_PW` is empty, a random password is generated
  and printed once to the logs.
- **Safe defaults**: compose publishes only noVNC, only on `127.0.0.1`. Raw VNC
  (5901) is not published.
- **PUID / PGID**: the desktop user's UID/GID are remapped at start to match
  the owner of your `./projects` folder.
- **Persistent home**: `/home` is a named volume, so settings, browser profiles
  and VS Code extensions survive container re-creation and upgrades.
- **VS Code extensions from env**: `VSCODE_EXTENSIONS=ms-python.python,...`.
- **Hooks**: root `/etc/xdesktop/init.d/*.sh` and user `~/.xdesktop/autostart.sh`.
- **Optional Docker CLI**: build with `INSTALL_DOCKER_CLI=true` and mount the socket.
- **Optional web file browser** for `./projects` (compose profile `files`).
- **Health check**: the container is marked unhealthy if X or noVNC stops
  responding. If a desktop process dies, the container exits and restarts.
- **Multi-arch** images (`linux/amd64`, `linux/arm64`), **signed**, with an
  **SBOM** attached.

Not supported: audio and GPU acceleration. Rendering is done in software by Xvnc.

## Quick start

```bash
git clone https://github.com/abhixops/xdesktop.git
cd xdesktop
cp env.example .env
# Optional: set VNC_PW in .env. Leave it empty to get a random password.
# Optional: set PUID/PGID to the output of `id -u` / `id -g`.
docker compose up -d
docker compose logs xdesktop   # shows the generated password if VNC_PW was empty
```

Open **<https://localhost:6080>** and accept the self-signed certificate
warning (see [Custom TLS certificates](#custom-tls-certificates) to avoid it).
Then enter the VNC password.

Your files go in `./projects` on the host. Inside the desktop they appear at
`/workspace`, and `~/Desktop/projects` links to the same place.

## Configuration

All settings are optional. Put them in `.env`; [`env.example`](env.example)
documents every one.

### Runtime environment variables

| Variable | Default | Description |
|---|---|---|
| `XDESKTOP_USER` | `xdesktop` | Desktop username. If it differs from the user built into the image, that user is renamed at start. |
| `PUID` / `PGID` | `1000` / `1000` | UID/GID of the desktop user. Set them to the owner of `./projects`. |
| `VNC_PW` | *(empty)* | VNC password. If empty, a random 12-character password is generated and printed **once** to the logs. Only the first 8 characters are used (VncAuth limit). |
| `RESOLUTION` | `1920x1080` | Initial screen size. With the default noVNC URL, the screen then resizes to fit the browser window. |
| `VNC_DEPTH` | `24` | Colour depth. |
| `DISPLAY_NUM` | `1` | X display number. The raw VNC port is `5900 + DISPLAY_NUM`. |
| `NOVNC_PORT` | `6080` | noVNC port inside the container. |
| `VNC_LISTEN` | `localhost` | `localhost`: raw VNC is only reachable inside the container. `all`: Xvnc accepts external connections (see [examples/raw-vnc](examples/raw-vnc/)). |
| `NOVNC_SSL_ONLY` | `true` | `true`: HTTPS only. `false`: also plain HTTP, for use behind a TLS-terminating reverse proxy. |
| `NOVNC_CERT` / `NOVNC_KEY` | *(empty)* | Paths to a custom certificate and key inside the container. |
| `ENABLE_SUDO` | `true` | Passwordless sudo for the desktop user. `false` removes it. |
| `TZ` | `UTC` | Time zone, e.g. `Europe/Berlin`. |
| `VSCODE_EXTENSIONS` | *(empty)* | Comma-separated extension IDs, installed in the background on start. Failures are logged to `~/.xdesktop/logs/vscode-extensions.log` and do not stop the container. |

### Compose-only variables

| Variable | Default | Description |
|---|---|---|
| `XDESKTOP_BIND` | `127.0.0.1` | Host address that noVNC is published on. |
| `NOVNC_HOST_PORT` | `6080` | Host port for noVNC. |
| `XDESKTOP_TAG` | `latest` | Image tag to run, e.g. `v2.0.0`. |
| `XDESKTOP_MEMORY` | `4g` | Memory limit. |
| `XDESKTOP_CPUS` | `2` | CPU limit. |
| `XDESKTOP_SHM_SIZE` | `1gb` | `/dev/shm` size. Browsers and Electron apps need more than Docker's 64 MB default. |
| `FILEBROWSER_PORT` | `8080` | Host port (on `127.0.0.1`) for the optional file browser. |
| `FILEBROWSER_TAG` | `latest` | File Browser image tag. |

### Build arguments

Used by `docker compose build`. Set them in `.env` too.

| Arg | Default | Description |
|---|---|---|
| `XDESKTOP_USER` | `xdesktop` | Username baked into the image. |
| `USER_UID` / `USER_GID` | `1000` / `1000` | UID/GID baked into the image. Compose fills these from `PUID` / `PGID`. |
| `INSTALL_VSCODE` | `true` | Install Visual Studio Code. |
| `INSTALL_FIREFOX` | `true` | Install Firefox (native deb from the Mozilla PPA, not snap). |
| `INSTALL_DOCKER_CLI` | `false` | Install `docker-ce-cli` and the compose plugin from Docker's apt repository. |
| `EXTRA_PACKAGES` | *(empty)* | Space-separated extra apt packages. |

### Volumes and ports

| Host | Container | Purpose |
|---|---|---|
| `./projects` | `/workspace` | Your files. `~/Desktop/projects` links here. |
| volume `xdesktop-home` | `/home` | Persistent home directory, seeded from `/etc/skel` on first run. |
| `127.0.0.1:6080` | `6080` | noVNC (HTTPS). |
| *(not published)* | `5901` | Raw VNC. See [examples/raw-vnc](examples/raw-vnc/). |

## Custom TLS certificates

noVNC uses the first of these that it finds:

1. `NOVNC_CERT` + `NOVNC_KEY`: paths to a certificate and key inside the container.
2. `/etc/ssl/novnc.pem`: a single PEM file that contains both certificate and key.
3. A self-signed certificate for `localhost` / `127.0.0.1`, stored in
   `~/.vnc/novnc.pem` and regenerated when it is within 7 days of expiring.

For example, with a certificate from [mkcert](https://github.com/FiloSottile/mkcert)
(trusted by your browser, so no warning):

```bash
mkdir -p certs && mkcert -cert-file certs/cert.pem -key-file certs/key.pem localhost 127.0.0.1
```

```yaml
# compose.override.yml (picked up automatically by docker compose)
services:
  xdesktop:
    environment:
      NOVNC_CERT: /certs/cert.pem
      NOVNC_KEY: /certs/key.pem
    volumes:
      - ./certs:/certs:ro
```

The key file must be readable by the desktop user (`PUID`).

## Security and remote access

- **Do not expose port 6080 or 5901 directly to the internet.** The only
  protection is the VNC password, and VncAuth uses only its **first 8
  characters**.
- For access over the internet, use [examples/caddy](examples/caddy/). It adds
  a real Let's Encrypt certificate and an HTTP basic-auth login in front of
  noVNC.
- For personal remote access, an SSH tunnel or a VPN (e.g. Tailscale or
  WireGuard) is simpler. Keep the default `127.0.0.1` binding and use
  `ssh -L 6080:127.0.0.1:6080 you@server`.
- Raw VNC (5901) is unencrypted. Only enable it with
  [examples/raw-vnc](examples/raw-vnc/), and only on localhost or a trusted network.
- The desktop user has passwordless sudo by default. Set `ENABLE_SUDO=false`
  if you don't need it.
- Mounting the Docker socket ([examples/docker-cli](examples/docker-cli/)) gives
  root-equivalent access to the host. The desktop user is added to the socket's
  group automatically. If that group is root (gid 0), which is the case with Docker
  Desktop on macOS/Windows, it is not added; a warning is printed and you need
  `sudo docker`.
- Starting the container with `docker run --user ...` is refused. Use
  `PUID`/`PGID` to change the user's IDs.

## Customization

### Hooks

- `/etc/xdesktop/init.d/*.sh`: run as **root**, in sorted order, on every start,
  before the desktop starts. If a hook exits non-zero, the container stops, so
  make hooks that are allowed to fail end with `|| true`.
- `~/.xdesktop/autostart.sh`: runs as the **desktop user**, in the background,
  after XFCE starts, if it is executable. It is in the persistent home, so you
  can edit it from inside the desktop.

See [examples/init-hooks](examples/init-hooks/) for working samples and how to
mount them.

### VS Code extensions

```bash
VSCODE_EXTENSIONS=ms-python.python,eamodio.gitlens,redhat.vscode-yaml
```

Extensions are installed in the background after start. Already installed ones
stay in the persistent home.

### Extra packages and image variants

Build your own variant with the build args:

```bash
# in .env
INSTALL_FIREFOX=false
EXTRA_PACKAGES="htop build-essential golang"
```

```bash
XDESKTOP_TAG=custom docker compose build
XDESKTOP_TAG=custom docker compose up -d
```

Use a custom `XDESKTOP_TAG` so a later `docker compose pull` doesn't replace
your build. For packages you only need occasionally, an init hook that runs
`apt-get install` also works, but it runs on every start.

### File browser

```bash
docker compose --profile files up -d
docker compose logs filebrowser   # first run prints the admin password
```

This starts [File Browser](https://github.com/filebrowser/filebrowser) on
<http://127.0.0.1:8080>, serving `./projects`. On first run it creates the
user `admin` with a **random password that is printed once** to its logs. If
you lose it, remove the `filebrowser-db` volume and start again. It runs as
`PUID:PGID`.

Note: the File Browser project has been archived upstream and gets no more
security fixes. Keep it on localhost.

### Examples

| Example | What it does |
|---|---|
| [examples/caddy](examples/caddy/) | Automatic HTTPS + basic auth with Caddy for internet access |
| [examples/raw-vnc](examples/raw-vnc/) | Publish raw VNC port 5901 for native VNC clients |
| [examples/docker-cli](examples/docker-cli/) | Docker CLI inside the desktop, using the host Docker socket |
| [examples/init-hooks](examples/init-hooks/) | Sample root init hook and user autostart script |

Each example is a compose override:
`docker compose -f docker-compose.yml -f examples/<name>/compose.override.yml up -d`.

## Upgrading from older versions

Version 2 changes several defaults:

- **`USERNAME` is now `XDESKTOP_USER`**. The old name collided with the
  `USERNAME` variable many host shells set. Rename it in your `.env`.
- **Projects mount at `/workspace`** instead of `/home/<user>/Desktop/projects`.
  `~/Desktop/projects` is now a symlink to `/workspace`, so old paths still work.
- **Port 5901 is no longer published.** Use [examples/raw-vnc](examples/raw-vnc/)
  if you need it.
- **Ports bind to `127.0.0.1` by default.** Set `XDESKTOP_BIND` to change that,
  but read [Security](#security-and-remote-access) first.
- **No default password.** `vncpassword` is gone. Set `VNC_PW` or read the
  generated one from `docker compose logs`.
- **Home is persisted** in the `xdesktop-home` volume. Files you previously kept
  only in the container's home were lost on re-creation; from now on they are
  kept. Use `docker compose down -v` to reset it.
- **The service is now named `xdesktop`** (was `vdi`). Run `docker compose down`
  with the old compose file before upgrading, or remove the old `vdi_app`
  container by hand.
- `.env` is no longer tracked in git. Copy `env.example` to `.env`.

## Troubleshooting

- **Browser certificate warning**: expected with the self-signed certificate.
  Accept it, or use a [custom certificate](#custom-tls-certificates).
- **`http://localhost:6080` doesn't load**: noVNC is HTTPS only by default. Use
  `https://`.
- **Forgot the generated password**: run `docker compose logs xdesktop`. If the
  logs were rotated, set `VNC_PW` in `.env` and `docker compose up -d`.
- **Password longer than 8 characters "doesn't matter"**: VncAuth only checks
  the first 8 characters. This is a limit of the protocol.
- **Permission denied in `./projects`**: set `PUID`/`PGID` in `.env` to the
  output of `id -u` / `id -g` for the owner of `./projects`, then
  `docker compose up -d`.
- **Container is `unhealthy` or restarting**: check
  `docker inspect --format '{{json .State.Health}}' $(docker compose ps -q xdesktop)`
  and `docker compose logs xdesktop`. The health check needs the X socket to
  exist and noVNC to answer on `NOVNC_PORT`.
- **VS Code or Firefox crashes**: increase `XDESKTOP_SHM_SIZE` and/or
  `XDESKTOP_MEMORY`.
- **Extension install failed**: see `~/.xdesktop/logs/vscode-extensions.log`
  inside the desktop.
- **Logs**: `docker compose logs -f xdesktop`.

## CI and releases

Images are built by GitHub Actions and published to `ghcr.io/abhixops/xdesktop`.
When a pull request is merged into `main`, its **title prefix** decides the
version bump:

| PR title prefix | Bump | Example |
|---|---|---|
| `release:` | major | `v1.4.2` → `v2.0.0` |
| `feat:` | minor | `v1.4.2` → `v1.5.0` |
| `fix:` | patch | `v1.4.2` → `v1.4.3` |

Other prefixes don't create a release. The tag is pushed, and the
multi-arch image is built, signed and published with an SBOM.

## Contributing

Contributions are always welcome! Please use one of the PR title prefixes above.

## Authors

- [@asabhi6776](https://www.github.com/abhixops)
- [@yogeshgowdagr](https://github.com/yogeshgowdagr)

## License

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
