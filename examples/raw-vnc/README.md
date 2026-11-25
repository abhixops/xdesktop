# Raw VNC access (port 5901)

By default only noVNC (HTTPS on 6080) is published. Xvnc listens on localhost
inside the container. This override sets `VNC_LISTEN=all` and publishes 5901 on
`${XDESKTOP_BIND:-127.0.0.1}`, so native VNC clients can connect.

```bash
docker compose -f docker-compose.yml -f examples/raw-vnc/compose.override.yml up -d
# then connect your VNC client to localhost:5901
```

Set `VNC_HOST_PORT` in `.env` to use a different host port. If you change
`DISPLAY_NUM`, change the container port in the override to `5900 + DISPLAY_NUM`.

## Security warning

- Raw VNC traffic is **unencrypted**.
- VncAuth only checks the **first 8 characters** of `VNC_PW`.
- Do not publish this port to the internet. For remote use, keep the default
  `127.0.0.1` binding and tunnel over SSH:

  ```bash
  ssh -L 5901:127.0.0.1:5901 user@your-server
  ```
