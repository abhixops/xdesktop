#!/bin/bash
# Runs as the desktop user (exec'd by entrypoint.sh via setpriv).
#
# Starts and supervises three processes:
#   1. Xtigervnc  - X server + VNC server on display :DISPLAY_NUM
#   2. xstartup   - the XFCE session (~/.vnc/xstartup)
#   3. websockify - serves noVNC and proxies WebSocket -> VNC
# If any of them exits, the others are stopped and the script exits non-zero
# so Docker's restart policy / healthcheck can react. SIGTERM (docker stop)
# shuts everything down cleanly and exits 0.
set -euo pipefail

log()  { printf '[start-desktop] %s\n' "$*"; }
die()  { printf '[start-desktop] ERROR: %s\n' "$*" >&2; exit 1; }

RESOLUTION="${RESOLUTION:-1920x1080}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_LISTEN="${VNC_LISTEN:-localhost}"
NOVNC_SSL_ONLY="${NOVNC_SSL_ONLY:-true}"
XDESKTOP_TLS_DIR="${XDESKTOP_TLS_DIR:-/run/xdesktop/tls}"
VNC_PORT=$((5900 + DISPLAY_NUM))
LOG_DIR="${HOME}/.xdesktop/logs"

export DISPLAY=":${DISPLAY_NUM}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"

[[ "${RESOLUTION}" =~ ^[0-9]+x[0-9]+$ ]] || die "RESOLUTION must look like 1920x1080 (got '${RESOLUTION}')"
[[ "${VNC_DEPTH}" =~ ^(16|24|32)$ ]] || die "VNC_DEPTH must be 16, 24 or 32 (got '${VNC_DEPTH}')"
[ -s "${HOME}/.vnc/passwd" ] || die "${HOME}/.vnc/passwd is missing"
[ -r "${XDESKTOP_TLS_DIR}/cert.pem" ] || die "TLS certificate ${XDESKTOP_TLS_DIR}/cert.pem is missing"

# VS Code itself reads $VSCODE_EXTENSIONS as its extensions *directory*, so the
# list must not leak into the session (or the `code` CLI) under that name.
EXTENSIONS_TO_INSTALL="${VSCODE_EXTENSIONS:-}"
unset VSCODE_EXTENSIONS

cd "${HOME}"
mkdir -p "${LOG_DIR}"
install -d -m 0700 "${XDG_RUNTIME_DIR}"
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

declare -A NAMES=()
PIDS=()
SHUTTING_DOWN=false

# shellcheck disable=SC2329  # invoked via trap
on_signal() { SHUTTING_DOWN=true; }
trap on_signal TERM INT HUP

stop_all() {
    local pid
    trap '' TERM INT HUP
    # Session first (its whole process group, so XFCE children go too),
    # then websockify, then the X server.
    if [ -n "${SESSION_PID:-}" ]; then kill -TERM -- "-${SESSION_PID}" 2>/dev/null || true; fi
    for pid in "${PIDS[@]}"; do kill -TERM "${pid}" 2>/dev/null || true; done
    for _ in $(seq 1 50); do
        local alive=false
        for pid in "${PIDS[@]}"; do
            if kill -0 "${pid}" 2>/dev/null; then alive=true; fi
        done
        [ "${alive}" = true ] || return 0
        sleep 0.1
    done
    log "processes did not exit in 5s, sending SIGKILL"
    if [ -n "${SESSION_PID:-}" ]; then kill -KILL -- "-${SESSION_PID}" 2>/dev/null || true; fi
    for pid in "${PIDS[@]}"; do kill -KILL "${pid}" 2>/dev/null || true; done
}

track() { PIDS+=("$1"); NAMES[$1]="$2"; }

# --- 1. Xtigervnc ------------------------------------------------------------
xvnc_args=(
    "${DISPLAY}"
    -geometry "${RESOLUTION}"
    -depth "${VNC_DEPTH}"
    -rfbport "${VNC_PORT}"
    -rfbauth "${HOME}/.vnc/passwd"
    -SecurityTypes VncAuth
    -AlwaysShared
    -AcceptSetDesktopSize
    -desktop "xdesktop"
    -nolisten tcp
)
if [ "${VNC_LISTEN}" = "localhost" ]; then
    xvnc_args+=(-localhost)
    log "VNC listening on 127.0.0.1:${VNC_PORT} only (VNC_LISTEN=localhost)"
else
    log "VNC listening on all interfaces, port ${VNC_PORT} (VNC_LISTEN=all)"
fi
log "starting Xtigervnc ${DISPLAY} ${RESOLUTION}x${VNC_DEPTH}"
Xtigervnc "${xvnc_args[@]}" &
track $! Xtigervnc

for _ in $(seq 1 100); do
    [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
    kill -0 "${PIDS[0]}" 2>/dev/null || die "Xtigervnc exited during startup"
    sleep 0.1
done
[ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] || { stop_all; die "X server socket did not appear"; }

# --- 2. XFCE session -----------------------------------------------------------
XSTARTUP="${HOME}/.vnc/xstartup"
if [ ! -x "${XSTARTUP}" ]; then
    XSTARTUP=/usr/local/lib/xdesktop/xstartup
fi
log "starting session ${XSTARTUP} (log: ${LOG_DIR}/session.log)"
# setsid: own process group so the whole session can be signalled at once.
setsid "${XSTARTUP}" > "${LOG_DIR}/session.log" 2>&1 &
SESSION_PID=$!
track "${SESSION_PID}" xstartup

# --- 3. websockify / noVNC ------------------------------------------------------
ws_args=(--web=/usr/share/novnc/ --cert="${XDESKTOP_TLS_DIR}/cert.pem")
if [ -r "${XDESKTOP_TLS_DIR}/key.pem" ]; then
    ws_args+=(--key="${XDESKTOP_TLS_DIR}/key.pem")
fi
case "${NOVNC_SSL_ONLY,,}" in
    false|0|no|off)
        log "noVNC on port ${NOVNC_PORT}: HTTPS and plain HTTP (NOVNC_SSL_ONLY=false)" ;;
    *)
        ws_args+=(--ssl-only)
        log "noVNC on port ${NOVNC_PORT}: HTTPS only" ;;
esac
websockify "${ws_args[@]}" "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
track $! websockify

# --- Optional: VS Code extensions (background, not supervised, non-fatal) -------
if [ -n "${EXTENSIONS_TO_INSTALL}" ] && command -v code >/dev/null 2>&1; then
    (
        IFS=',' read -ra exts <<< "${EXTENSIONS_TO_INSTALL}"
        for ext in "${exts[@]}"; do
            ext="${ext//[[:space:]]/}"
            [ -n "${ext}" ] || continue
            echo "[$(date -Is)] installing ${ext}"
            code --install-extension "${ext}" || echo "[$(date -Is)] FAILED: ${ext}"
        done
        echo "[$(date -Is)] done"
    ) >> "${LOG_DIR}/vscode-extensions.log" 2>&1 < /dev/null &
    log "installing VS Code extensions in background (log: ${LOG_DIR}/vscode-extensions.log)"
fi

log "desktop ready: https://localhost:${NOVNC_PORT}/"

# --- Supervise ---------------------------------------------------------------------
rc=0
exited_pid=""
if [ "${SHUTTING_DOWN}" = false ]; then
    wait -n -p exited_pid "${PIDS[@]}" || rc=$?
fi

if [ "${SHUTTING_DOWN}" = true ]; then
    log "received stop signal, shutting down"
    stop_all
    exit 0
fi

log "${NAMES[${exited_pid}]:-a supervised process} exited unexpectedly (status ${rc}); stopping container"
stop_all
[ "${rc}" -ne 0 ] || rc=1
exit "${rc}"
