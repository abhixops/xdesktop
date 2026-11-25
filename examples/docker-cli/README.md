# Docker CLI inside the desktop

This override builds the image locally with `INSTALL_DOCKER_CLI=true`. That
installs `docker-ce-cli` and the compose plugin from Docker's apt repository.
It also mounts the host's `/var/run/docker.sock`. At start, the entrypoint adds
the desktop user to a group with the socket's GID, so `docker` works without
sudo.

```bash
docker compose -f docker-compose.yml -f examples/docker-cli/compose.override.yml up -d --build
```

The local image is tagged `xdesktop-local:docker-cli` with `pull_policy: build`,
so it does not overwrite `ghcr.io/abhixops/xdesktop`.

## Security warning

Mounting the Docker socket gives the container **full root-equivalent control of
the host**. Any process in the desktop, including a browser exploit or a
malicious VS Code extension, can start privileged containers and read or
modify any host file. Only use this on a machine you would also trust with
root, and never combine it with exposing the desktop to the internet.
