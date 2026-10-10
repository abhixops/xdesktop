# Xdesktop

Xdesktop is a lightweight containerized Virtual Desktop Infrastructure (VDI) solution that runs an Ubuntu 24.04 GUI (XFCE) in Docker, pre-configured with Visual Studio Code, Firefox, Python development tools, and terminal utilities.

## Features

- **Lightweight VDI Solution**: Runs directly in Docker without the overhead of heavy virtual machines.
- **In-Browser Access (noVNC)**: Connect directly via web browser using HTML5/WebSocket (port `6080`).
- **Direct VDI Access**: Connect with any standard VNC client (port `5901`).
- **Preinstalled Developer Tools**: Visual Studio Code, Firefox (native deb), Python 3, Git, Tmux, Vim, and Nano.
- **Multi-Architecture**: Supports both `linux/amd64` and `linux/arm64`.
- **Hardened Security**: Dynamic runtime credentials, dynamic TLS certificate generation, non-root execution, and graceful process lifecycle management.

## Quick Start

```bash
git clone https://github.com/abhixops/xdesktop.git
cd xdesktop
docker compose up -d
```

Once running, access your desktop:
- **Web Browser (noVNC)**: Navigate to `https://localhost:6080` (or `http://localhost:6080`)
- **VNC Client**: Connect to `localhost:5901`

## Environment Variables

Configure your container via `.env` or Docker Compose environment variables:

| Variable | Default | Description |
|---|---|---|
| `USERNAME` | `abhishek` | Non-root Linux user account |
| `VNC_PW` | `vncpassword` | Password for VNC connection |
| `RESOLUTION` | `1920x1080` | Virtual display screen resolution |
| `VNC_DEPTH` | `24` | Screen color bit depth |

## Contributing

Contributions are always welcome!

## Authors

- [@asabhi6776](https://www.github.com/abhixops)
- [@yogeshgowdagr](https://github.com/yogeshgowdagr)

## License

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)
