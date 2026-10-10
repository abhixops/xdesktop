#!/bin/bash
set -e

# Pin Mozilla Team PPA to prevent Ubuntu from installing the snap wrapper for Firefox
mkdir -p /etc/apt/preferences.d
cat << 'EOF' > /etc/apt/preferences.d/mozilla-firefox
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: firefox
Pin: version 1:1snap1-0ubuntu2
Pin-Priority: -1
EOF