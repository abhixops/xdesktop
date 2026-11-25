#!/usr/bin/env bash
# Example user autostart script for xdesktop.
#
# If ~/.xdesktop/autostart.sh exists and is executable, it runs as the desktop
# user, in the background, after XFCE has started. DISPLAY is already set.
# It lives in the persistent home volume, so edits survive container restarts.

echo "[autostart] $(date -Is) desktop started for $(id -un)" >> "${HOME}/.xdesktop/autostart.log"

# Examples:
# xfce4-terminal --working-directory=/workspace &
# code /workspace &
