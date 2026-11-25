#!/usr/bin/env bash
# Example root init hook for xdesktop.
#
# Every /etc/xdesktop/init.d/*.sh is run as ROOT, in sorted order, after the
# desktop user is set up and before the desktop starts. Use hooks for
# system-level setup: extra apt packages, /etc config, certificates, ...
# Keep hooks idempotent: they run on every container start.
set -euo pipefail

user="${XDESKTOP_USER:-xdesktop}"
home="/home/${user}"

echo "[10-example] running as $(id -un) for desktop user ${user}"

# Example: install a package only if it is missing (needs network access).
# if ! command -v htop >/dev/null 2>&1; then
#     apt-get update && apt-get install -y --no-install-recommends htop
#     rm -rf /var/lib/apt/lists/*
# fi

# Install the sample user autostart script if the user does not have one yet.
template=/etc/xdesktop/examples/autostart.sh
target="${home}/.xdesktop/autostart.sh"
if [ -f "$template" ] && [ -d "$home" ] && [ ! -e "$target" ]; then
    install -d -o "${PUID:-1000}" -g "${PGID:-1000}" "${home}/.xdesktop"
    install -m 0755 -o "${PUID:-1000}" -g "${PGID:-1000}" "$template" "$target"
    echo "[10-example] installed ${target}"
fi
