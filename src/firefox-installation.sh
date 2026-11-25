#!/bin/bash
# Configure the Mozilla Team PPA so the native Firefox .deb is installed instead
# of Ubuntu's snap transitional package (snapd does not work inside containers).
# Written by hand instead of `add-apt-repository` so software-properties-common
# (and its Python/GLib dependency tree) is not needed in the image.
set -euo pipefail

# Mozilla Team PPA signing key (Launchpad PPA for Mozilla Team)
readonly KEY_FPR="0AB215679C571D1C8325275B9BDB3D89CE49EC21"
readonly KEYRING="/etc/apt/keyrings/mozillateam.asc"

# shellcheck source=/dev/null
. /etc/os-release

install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x${KEY_FPR}" -o "${KEYRING}"
chmod 0644 "${KEYRING}"

# Refuse to continue unless the downloaded key is exactly the expected one.
actual_fpr="$(gpg --show-keys --with-colons "${KEYRING}" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "${actual_fpr}" != "${KEY_FPR}" ]; then
    echo "Mozilla PPA key fingerprint mismatch: got '${actual_fpr}', expected '${KEY_FPR}'" >&2
    exit 1
fi

cat > /etc/apt/sources.list.d/mozillateam.sources <<SOURCES
Types: deb
URIs: https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu
Suites: ${VERSION_CODENAME}
Components: main
Signed-By: ${KEYRING}
SOURCES

# Prefer the PPA over the Ubuntu archive and never install the snap wrapper.
install -d -m 0755 /etc/apt/preferences.d
cat > /etc/apt/preferences.d/mozilla-firefox <<'PIN'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: firefox
Pin: version 1:1snap*
Pin-Priority: -1
PIN
