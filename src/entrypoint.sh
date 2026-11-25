#!/bin/bash
# xdesktop container entrypoint (runs as root under tini).
#
# Prepares the desktop user (name, UID/GID, home, sudo, docker socket access),
# the VNC password and the noVNC TLS certificate, runs root init hooks, then
# drops privileges with setpriv and execs start-desktop.sh as the desktop user.
set -euo pipefail

log()  { printf '[entrypoint] %s\n' "$*"; }
warn() { printf '[entrypoint] WARNING: %s\n' "$*" >&2; }
die()  { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

# Values baked in at build time (build args XDESKTOP_USER / USER_UID / USER_GID).
# shellcheck source=/dev/null
. /etc/xdesktop/build.env

XDESKTOP_USER="${XDESKTOP_USER:-${BUILD_USER}}"
PUID="${PUID:-${BUILD_UID}}"
PGID="${PGID:-${BUILD_GID}}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_LISTEN="${VNC_LISTEN:-localhost}"
NOVNC_SSL_ONLY="${NOVNC_SSL_ONLY:-true}"
ENABLE_SUDO="${ENABLE_SUDO:-true}"
TZ="${TZ:-UTC}"

readonly STATE_USER_FILE=/etc/xdesktop/current-user
readonly SUDOERS_FILE=/etc/sudoers.d/xdesktop-user
readonly RUN_DIR=/run/xdesktop

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        0|false|no|off|"") return 1 ;;
        *) die "invalid boolean value '$1' (use true/false)" ;;
    esac
}

validate() {
    [[ "${XDESKTOP_USER}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
        || die "XDESKTOP_USER '${XDESKTOP_USER}' is not a valid user name"
    [[ "${PUID}" =~ ^[0-9]+$ ]] || die "PUID must be numeric (got '${PUID}')"
    [[ "${PGID}" =~ ^[0-9]+$ ]] || die "PGID must be numeric (got '${PGID}')"
    [ "${PUID}" -ne 0 ] || die "PUID=0 is not supported; the desktop must not run as root"
    [ "${PGID}" -ne 0 ] || die "PGID=0 is not supported"
    [[ "${DISPLAY_NUM}" =~ ^[0-9]+$ ]] || die "DISPLAY_NUM must be numeric"
    [[ "${NOVNC_PORT}" =~ ^[0-9]+$ ]] || die "NOVNC_PORT must be numeric"
    case "${VNC_LISTEN}" in
        localhost|all) ;;
        *) die "VNC_LISTEN must be 'localhost' or 'all' (got '${VNC_LISTEN}')" ;;
    esac
    is_true "${NOVNC_SSL_ONLY}" || true
    is_true "${ENABLE_SUDO}" || true
}

setup_timezone() {
    if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
        ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
        printf '%s\n' "${TZ}" > /etc/timezone
    else
        warn "unknown timezone TZ='${TZ}', keeping $(cat /etc/timezone 2>/dev/null || echo UTC)"
    fi
}

# Rename the image's desktop user and remap its UID/GID to match the host.
setup_user() {
    local current group current_gid other_group
    current="$(cat "${STATE_USER_FILE}")"

    if [ "${current}" != "${XDESKTOP_USER}" ]; then
        if id -u "${XDESKTOP_USER}" >/dev/null 2>&1; then
            die "user '${XDESKTOP_USER}' already exists in the image and is not the desktop user"
        fi
        log "renaming user '${current}' -> '${XDESKTOP_USER}'"
        usermod -l "${XDESKTOP_USER}" -d "/home/${XDESKTOP_USER}" "${current}"
        if getent group "${current}" >/dev/null && ! getent group "${XDESKTOP_USER}" >/dev/null; then
            groupmod -n "${XDESKTOP_USER}" "${current}"
        fi
        if [ -f "/etc/sudoers.d/${current}" ]; then rm -f "/etc/sudoers.d/${current}"; fi
        printf '%s\n' "${XDESKTOP_USER}" > "${STATE_USER_FILE}"
    fi

    group="$(id -gn "${XDESKTOP_USER}")"
    current_gid="$(id -g "${XDESKTOP_USER}")"
    if [ "${current_gid}" != "${PGID}" ]; then
        other_group="$(getent group "${PGID}" | cut -d: -f1 || true)"
        if [ -n "${other_group}" ]; then
            log "using existing group '${other_group}' (gid ${PGID}) as primary group"
            usermod -g "${PGID}" "${XDESKTOP_USER}"
        else
            log "changing gid of group '${group}' ${current_gid} -> ${PGID}"
            groupmod -g "${PGID}" "${group}"
        fi
    fi

    if [ "$(id -u "${XDESKTOP_USER}")" != "${PUID}" ]; then
        log "changing uid of '${XDESKTOP_USER}' -> ${PUID}"
        usermod -o -u "${PUID}" "${XDESKTOP_USER}"
    fi
}

setup_home() {
    local home="/home/${XDESKTOP_USER}"
    install -d -m 0755 /home

    if [ ! -d "${home}" ] || [ -z "$(ls -A "${home}" 2>/dev/null)" ]; then
        log "seeding ${home} from /etc/skel"
        install -d -m 0750 "${home}"
        cp -a /etc/skel/. "${home}/"
        chown -R "${PUID}:${PGID}" "${home}"
    elif [ "$(stat -c '%u:%g' "${home}")" != "${PUID}:${PGID}" ]; then
        log "fixing ownership of ${home} for ${PUID}:${PGID}"
        chown -R "${PUID}:${PGID}" "${home}"
    fi

    # Files the image relies on that an older/persistent home may be missing.
    local f
    for f in .vnc/xstartup .vscode/argv.json; do
        if [ ! -e "${home}/${f}" ] && [ -e "/etc/skel/${f}" ]; then
            install -d -o "${PUID}" -g "${PGID}" "$(dirname "${home}/${f}")"
            cp -a "/etc/skel/${f}" "${home}/${f}"
            chown "${PUID}:${PGID}" "${home}/${f}"
        fi
    done
    install -d -m 0700 -o "${PUID}" -g "${PGID}" "${home}/.vnc"
    install -d -m 0755 -o "${PUID}" -g "${PGID}" "${home}/.xdesktop" "${home}/.xdesktop/logs" "${home}/Desktop"

    # ~/Desktop/projects -> /workspace (never chown /workspace itself).
    if [ -d /workspace ]; then
        local link="${home}/Desktop/projects"
        if [ -L "${link}" ] || [ ! -e "${link}" ]; then
            ln -sfn /workspace "${link}"
            chown -h "${PUID}:${PGID}" "${link}"
        else
            warn "${link} exists and is not a symlink; not linking /workspace"
        fi
        if [ "$(stat -c %u /workspace)" = "0" ] && [ -z "$(ls -A /workspace 2>/dev/null)" ]; then
            # Nothing mounted (empty image directory): hand it to the user, non-recursively.
            chown "${PUID}:${PGID}" /workspace
        elif [ "$(stat -c %u /workspace)" != "${PUID}" ]; then
            warn "/workspace is owned by uid $(stat -c %u /workspace), not PUID=${PUID}; set PUID/PGID to your host user's ids"
        fi
    fi
}

setup_sudo() {
    if is_true "${ENABLE_SUDO}"; then
        printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${XDESKTOP_USER}" > "${SUDOERS_FILE}"
        chmod 0440 "${SUDOERS_FILE}"
        visudo -cqf "${SUDOERS_FILE}" || die "generated sudoers file is invalid"
    else
        rm -f "${SUDOERS_FILE}"
        log "sudo disabled for '${XDESKTOP_USER}' (ENABLE_SUDO=false)"
    fi
}

# Give the user access to a bind-mounted Docker socket via its group id.
setup_docker_socket() {
    local sock=/var/run/docker.sock gid group
    [ -S "${sock}" ] || return 0
    gid="$(stat -c %g "${sock}")"
    if [ "${gid}" = "0" ]; then
        warn "${sock} is owned by group root (gid 0); not adding '${XDESKTOP_USER}' to root group. Use sudo docker, or chgrp the socket on the host."
        return 0
    fi
    group="$(getent group "${gid}" | cut -d: -f1 || true)"
    if [ -z "${group}" ]; then
        group=docker-host
        getent group "${group}" >/dev/null && group="docker-host-${gid}"
        groupadd -g "${gid}" "${group}"
    fi
    usermod -aG "${group}" "${XDESKTOP_USER}"
    log "docker socket: '${XDESKTOP_USER}' added to group '${group}' (gid ${gid})"
}

setup_vnc_password() {
    local passwd_file="/home/${XDESKTOP_USER}/.vnc/passwd" pw="${VNC_PW:-}" generated=false
    if [ -z "${pw}" ]; then
        while [ "${#pw}" -lt 12 ]; do
            pw="${pw}$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
        done
        pw="${pw:0:12}"
        generated=true
    elif [ "${#pw}" -gt 8 ]; then
        warn "VNC_PW is longer than 8 characters; VNC authentication only uses the first 8"
    elif [ "${#pw}" -lt 6 ]; then
        warn "VNC_PW is shorter than 6 characters; consider a longer password"
    fi

    (umask 077 && printf '%s\n' "${pw}" | vncpasswd -f > "${passwd_file}")
    chown "${PUID}:${PGID}" "${passwd_file}"
    chmod 0600 "${passwd_file}"

    if [ "${generated}" = true ]; then
        printf '\n'
        printf '==============================================================\n'
        printf ' VNC_PW not set - generated a random password for this run:\n'
        printf '     %s\n' "${pw}"
        printf ' (VNC authentication uses only the first 8 characters.)\n'
        printf ' Set VNC_PW to choose your own.\n'
        printf '==============================================================\n\n'
    fi
    unset pw VNC_PW
}

# Copy a cert/key into a location readable by the unprivileged user.
stage_tls_file() {
    local src="$1" dst="$2"
    [ -r "${src}" ] || die "TLS file '${src}' does not exist or is not readable"
    install -m 0600 -o "${PUID}" -g "${PGID}" "${src}" "${dst}"
}

setup_tls() {
    local tls_dir="${RUN_DIR}/tls" home="/home/${XDESKTOP_USER}"
    install -d -m 0700 -o "${PUID}" -g "${PGID}" "${tls_dir}"
    rm -f "${tls_dir}"/*

    if [ -n "${NOVNC_CERT:-}" ]; then
        log "TLS: using custom certificate ${NOVNC_CERT}"
        stage_tls_file "${NOVNC_CERT}" "${tls_dir}/cert.pem"
        if [ -n "${NOVNC_KEY:-}" ]; then
            stage_tls_file "${NOVNC_KEY}" "${tls_dir}/key.pem"
        fi
    elif [ -n "${NOVNC_KEY:-}" ]; then
        die "NOVNC_KEY is set but NOVNC_CERT is not"
    elif [ -f /etc/ssl/novnc.pem ]; then
        log "TLS: using /etc/ssl/novnc.pem"
        stage_tls_file /etc/ssl/novnc.pem "${tls_dir}/cert.pem"
    else
        local pem="${home}/.vnc/novnc.pem" regen=false
        if [ ! -s "${pem}" ]; then
            regen=true
        elif ! openssl x509 -checkend 604800 -noout -in "${pem}" >/dev/null 2>&1; then
            log "TLS: self-signed certificate expires within 7 days"
            regen=true
        elif ! openssl x509 -noout -ext subjectAltName -in "${pem}" 2>/dev/null | grep -q 'DNS:localhost'; then
            log "TLS: self-signed certificate has no subjectAltName"
            regen=true
        fi
        if [ "${regen}" = true ]; then
            log "TLS: generating self-signed certificate (CN=localhost, SAN DNS:localhost, IP:127.0.0.1)"
            local tmp
            tmp="$(mktemp -d)"
            openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
                -keyout "${tmp}/key.pem" -out "${tmp}/cert.pem" \
                -subj "/O=xdesktop/CN=localhost" \
                -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1 \
                || die "failed to generate self-signed certificate"
            (umask 077 && cat "${tmp}/key.pem" "${tmp}/cert.pem" > "${pem}")
            rm -rf "${tmp}"
            chown "${PUID}:${PGID}" "${pem}"
            chmod 0600 "${pem}"
        fi
        ln -sfn "${pem}" "${tls_dir}/cert.pem"
    fi
}

cleanup_x_locks() {
    install -d -m 1777 /tmp/.X11-unix /tmp/.ICE-unix
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
}

run_init_hooks() {
    local hook
    [ -d /etc/xdesktop/init.d ] || return 0
    export XDESKTOP_USER PUID PGID
    export XDESKTOP_HOME="/home/${XDESKTOP_USER}"
    while IFS= read -r hook; do
        log "running init hook ${hook}"
        bash "${hook}" || die "init hook ${hook} failed"
    done < <(find /etc/xdesktop/init.d -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort)
}

main() {
    if [ "$(id -u)" -ne 0 ]; then
        die "the entrypoint must start as root (it drops privileges itself); use PUID/PGID instead of 'docker run --user'"
    fi

    validate
    setup_timezone
    setup_user
    setup_home
    setup_sudo
    setup_docker_socket
    install -d -m 0755 "${RUN_DIR}"
    setup_vnc_password
    setup_tls
    cleanup_x_locks
    run_init_hooks

    local home="/home/${XDESKTOP_USER}"
    cd "${home}"
    log "starting desktop as ${XDESKTOP_USER} (uid ${PUID}, gid ${PGID})"
    exec setpriv --reuid="${PUID}" --regid="${PGID}" --init-groups \
        env HOME="${home}" USER="${XDESKTOP_USER}" LOGNAME="${XDESKTOP_USER}" SHELL=/bin/bash \
            XDESKTOP_TLS_DIR="${RUN_DIR}/tls" \
        /usr/local/bin/start-desktop.sh
}

main "$@"
