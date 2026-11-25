# xdesktop behind Caddy (HTTPS + basic auth)

Use this to reach xdesktop from the internet. [Caddy](https://caddyserver.com)
gets a Let's Encrypt certificate for your domain and asks for a username and
password before anything reaches noVNC. The VNC password is still required
after that.

## Prerequisites

- A DNS name (e.g. `desktop.example.com`) pointing at the host.
- Ports 80 and 443 reachable from the internet (Let's Encrypt validates on them).

## Setup

1. Create a password hash:

   ```bash
   docker run --rm caddy:2 caddy hash-password --plaintext 'a-long-passphrase'
   ```

2. Add to `.env` in the repo root. Use **single quotes** around the hash,
   otherwise Compose treats the `$` characters in it as variables:

   ```bash
   XDESKTOP_DOMAIN=desktop.example.com
   CADDY_EMAIL=you@example.com
   BASIC_AUTH_USER=me
   BASIC_AUTH_HASH='$2a$14$....'
   ```

3. Start it from the repo root:

   ```bash
   docker compose -f docker-compose.yml -f examples/caddy/compose.override.yml up -d
   ```

4. Open `https://desktop.example.com`.

## How it works

- [`compose.override.yml`](compose.override.yml) sets `NOVNC_SSL_ONLY=false` on
  xdesktop and removes its published port (`ports: !reset []`, needs Docker
  Compose 2.24 or newer). xdesktop is then only reachable on the internal
  compose network.
- [`Caddyfile`](Caddyfile) proxies to `http://xdesktop:6080`. TLS ends at Caddy.
  The hop from Caddy to xdesktop is plain HTTP, but it never leaves the Docker
  network on that host. This avoids proxying to xdesktop's self-signed
  certificate with `tls_insecure_skip_verify`.
- Caddy passes WebSocket upgrades through automatically, so noVNC's
  `/websockify` connection works without extra configuration.
- Certificates live in the `caddy-data` volume and renew automatically.
