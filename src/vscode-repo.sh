#!/bin/bash
# Configure Microsoft's APT repository for Visual Studio Code.
set -euo pipefail

# Microsoft (Release signing) <gpgsecurity@microsoft.com>
readonly KEY_FPR="BC528686B50D79E339D3721CEB3E94ADBE1229CF"
readonly KEYRING="/usr/share/keyrings/microsoft.gpg"

install -d -m 0755 /usr/share/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o "${KEYRING}"
chmod 0644 "${KEYRING}"

actual_fpr="$(gpg --show-keys --with-colons "${KEYRING}" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "${actual_fpr}" != "${KEY_FPR}" ]; then
    echo "Microsoft key fingerprint mismatch: got '${actual_fpr}', expected '${KEY_FPR}'" >&2
    exit 1
fi

# Same file name/format the `code` package's postinst manages, so it does not
# add a duplicate source. Also tell the postinst not to touch the repo config.
cat > /etc/apt/sources.list.d/vscode.sources <<SOURCES
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: ${KEYRING}
SOURCES
echo "code code/add-microsoft-repo boolean false" | debconf-set-selections
