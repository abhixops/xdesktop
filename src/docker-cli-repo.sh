#!/bin/bash
# Configure Docker's official APT repository (docker-ce-cli, docker-compose-plugin).
set -euo pipefail

# Docker Release (CE deb) <docker@docker.com>
readonly KEY_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
readonly KEYRING="/etc/apt/keyrings/docker.asc"

# shellcheck source=/dev/null
. /etc/os-release

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${KEYRING}"
chmod 0644 "${KEYRING}"

actual_fpr="$(gpg --show-keys --with-colons "${KEYRING}" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "${actual_fpr}" != "${KEY_FPR}" ]; then
    echo "Docker key fingerprint mismatch: got '${actual_fpr}', expected '${KEY_FPR}'" >&2
    exit 1
fi

cat > /etc/apt/sources.list.d/docker.sources <<SOURCES
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: ${KEYRING}
SOURCES
