#!/bin/bash
set -e

# Cleanup stale X11 / VNC locks from previous container runs
rm -rf /tmp/.X*-lock /tmp/.X11-unix/X*

# Configuration parameters with sensible defaults
VNC_PW="${VNC_PW:-vncpassword}"
RESOLUTION="${RESOLUTION:-1920x1080}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
VNC_PORT=$((5900 + DISPLAY_NUM))
NOVNC_PORT="${NOVNC_PORT:-6080}"

# Setup runtime VNC password (prevents hardcoded credentials in Docker image layers)
mkdir -p "$HOME/.vnc"
echo "$VNC_PW" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

# Ensure xstartup exists and is executable
if [ ! -f "$HOME/.vnc/xstartup" ] && [ -f "/etc/skel/.vnc/xstartup" ]; then
    cp "/etc/skel/.vnc/xstartup" "$HOME/.vnc/xstartup"
fi
[ -f "$HOME/.vnc/xstartup" ] && chmod +x "$HOME/.vnc/xstartup"

# Handle SSL Certificate for noVNC / websockify
CERT_PATH="/etc/ssl/novnc.pem"
if [ ! -f "$CERT_PATH" ]; then
    CERT_PATH="$HOME/.vnc/novnc.pem"
    if [ ! -f "$CERT_PATH" ]; then
        echo "Generating fresh self-signed TLS certificate for noVNC..."
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout "$CERT_PATH" \
            -out "$CERT_PATH" \
            -days 365 \
            -subj "/C=US/ST=State/L=City/O=xdesktop/CN=localhost" 2>/dev/null
        chmod 600 "$CERT_PATH"
    fi
fi

# Start TightVNC server
echo "Starting TightVNC server on display :${DISPLAY_NUM} (Resolution: ${RESOLUTION}, Depth: ${VNC_DEPTH})..."
vncserver -depth "$VNC_DEPTH" -geometry "$RESOLUTION" ":${DISPLAY_NUM}"

# Start websockify for noVNC
echo "Starting websockify (noVNC) on port ${NOVNC_PORT} proxying to localhost:${VNC_PORT}..."
websockify --web=/usr/share/novnc/ --cert="$CERT_PATH" "$NOVNC_PORT" "localhost:${VNC_PORT}" &
WEBSOCKIFY_PID=$!

# Trap signals for graceful shutdown
cleanup() {
    echo "Termination signal received, shutting down gracefully..."
    kill -TERM "$WEBSOCKIFY_PID" 2>/dev/null || true
    vncserver -kill ":${DISPLAY_NUM}" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# Wait for websockify process
wait "$WEBSOCKIFY_PID"
