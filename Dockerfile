# syntax=docker/dockerfile:1
#
# xdesktop - Ubuntu 24.04 XFCE desktop served over noVNC (TigerVNC + websockify).
#
# Base image: ubuntu:24.04 (pinned by multi-arch index digest; Dependabot bumps it).
FROM ubuntu:24.04@sha256:562111b88caa79c71391c0c4d3c2114a7d5c35915c20561fd893cb1e07929e6b

LABEL org.opencontainers.image.title="xdesktop" \
      org.opencontainers.image.description="Ubuntu 24.04 XFCE desktop in Docker, accessed via noVNC" \
      org.opencontainers.image.source="https://github.com/abhixops/xdesktop" \
      org.opencontainers.image.licenses="MIT" \
      maintainer="github.com/abhixops"

ARG XDESKTOP_USER=xdesktop
ARG USER_UID=1000
ARG USER_GID=1000
ARG INSTALL_VSCODE=true
ARG INSTALL_FIREFOX=true
ARG INSTALL_DOCKER_CLI=false
ARG EXTRA_PACKAGES=""
# Build-time only (ARG, not ENV) so it does not leak into the runtime environment.
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Base prerequisites, locale and timezone data.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gpg \
        locales \
        tzdata \
    && sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 \
    && ln -sf /usr/share/zoneinfo/UTC /etc/localtime \
    && echo UTC > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# Third-party APT repositories (each verifies its signing key fingerprint).
COPY src/firefox-installation.sh src/vscode-repo.sh src/docker-cli-repo.sh /tmp/repo-setup/
RUN if [ "${INSTALL_FIREFOX}" = "true" ]; then bash /tmp/repo-setup/firefox-installation.sh; fi \
    && if [ "${INSTALL_VSCODE}" = "true" ]; then bash /tmp/repo-setup/vscode-repo.sh; fi \
    && if [ "${INSTALL_DOCKER_CLI}" = "true" ]; then bash /tmp/repo-setup/docker-cli-repo.sh; fi \
    && rm -rf /tmp/repo-setup

# Desktop (XFCE), TigerVNC + noVNC stack, fonts, developer tools and optional apps.
# Package versions are not pinned: this image tracks Ubuntu 24.04 security updates.
# SC3054: hadolint lints RUN as POSIX sh, but SHELL above makes it bash (arrays OK).
# hadolint ignore=DL3008,SC3054
RUN optional=() \
    && if [ "${INSTALL_FIREFOX}" = "true" ]; then optional+=(firefox); fi \
    && if [ "${INSTALL_VSCODE}" = "true" ]; then optional+=(code); fi \
    && if [ "${INSTALL_DOCKER_CLI}" = "true" ]; then optional+=(docker-ce-cli docker-compose-plugin); fi \
    && read -ra extra <<< "${EXTRA_PACKAGES}" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        xfce4 \
        xfce4-goodies \
        xfce4-terminal \
        tigervnc-standalone-server \
        tigervnc-tools \
        novnc \
        websockify \
        tini \
        sudo \
        openssl \
        dbus-x11 \
        at-spi2-core \
        xauth \
        x11-xserver-utils \
        x11-utils \
        xterm \
        xfonts-base \
        xfonts-75dpi \
        xfonts-100dpi \
        xfonts-scalable \
        fonts-dejavu \
        fonts-noto-core \
        fonts-noto-color-emoji \
        fonts-firacode \
        adwaita-icon-theme \
        procps \
        less \
        git \
        openssh-client \
        tmux \
        vim \
        nano \
        python3 \
        python3-pip \
        python3-cairo \
        alacarte \
        "${optional[@]}" \
        "${extra[@]}" \
    && apt-get purge -y \
        xfce4-screensaver \
        light-locker \
        xscreensaver \
        gnome-screensaver \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Desktop defaults: wallpaper, no screen blanking/locking, noVNC landing page,
# session hooks and a sandbox-less VS Code launcher (package files untouched).
COPY assets/bg-l2.png /usr/share/backgrounds/xfce/xfce-custom.png
COPY src/xfce4-desktop.xml src/xfce4-power-manager.xml src/xfce4-screensaver.xml \
     /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/
COPY src/novnc-index.html /usr/share/novnc/index.html
COPY src/xdesktop-autostart.desktop /etc/xdg/autostart/xdesktop-autostart.desktop
COPY src/xstartup src/session-autostart /usr/local/lib/xdesktop/
COPY src/xstartup-user /etc/skel/.vnc/xstartup
COPY src/vscode-argv.json /etc/skel/.vscode/argv.json
COPY src/code-wrapper /usr/local/bin/code
COPY src/entrypoint.sh src/start-desktop.sh src/xdesktop-healthcheck /usr/local/bin/

# - Panel: use the stock default layout instead of the first-run "which panel?" dialog.
# - VS Code menu entries: copies of the package's .desktop files in
#   /usr/local/share/applications (searched before /usr/share) that launch with
#   --no-sandbox, so the XFCE menu works too. Fails the build if none are found.
# hadolint ignore=SC3054
RUN chmod 0755 /usr/local/bin/code /usr/local/bin/entrypoint.sh /usr/local/bin/start-desktop.sh \
        /usr/local/bin/xdesktop-healthcheck /usr/local/lib/xdesktop/xstartup \
        /usr/local/lib/xdesktop/session-autostart /etc/skel/.vnc/xstartup \
    && chmod 0700 /etc/skel/.vnc \
    && if [ -f /etc/xdg/xfce4/panel/default.xml ]; then \
        cp /etc/xdg/xfce4/panel/default.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml; \
    fi \
    && if [ "${INSTALL_VSCODE}" = "true" ]; then \
        install -d /usr/local/share/applications \
        && mapfile -t code_desktop < <(grep -l '^Exec=/usr/share/code/code' /usr/share/applications/*.desktop) \
        && [ "${#code_desktop[@]}" -gt 0 ] \
        && for f in "${code_desktop[@]}"; do \
            sed -E 's#^(Exec=/usr/share/code/code)( |$)#\1 --no-sandbox\2#' \
                "${f}" > "/usr/local/share/applications/$(basename "${f}")"; \
        done; \
    else \
        rm -f /usr/local/bin/code /etc/skel/.vscode/argv.json && rmdir /etc/skel/.vscode; \
    fi \
    && install -d -m 0755 /etc/xdesktop /etc/xdesktop/init.d /workspace

# Desktop user. Ubuntu's stock 'ubuntu' user (uid/gid 1000) is removed first.
# Name/UID/GID can still be changed at runtime (XDESKTOP_USER, PUID, PGID).
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu 2>/dev/null || userdel ubuntu; fi \
    && if getent group ubuntu >/dev/null; then groupdel ubuntu; fi \
    && groupadd --gid "${USER_GID}" "${XDESKTOP_USER}" \
    && useradd --create-home --shell /bin/bash --uid "${USER_UID}" --gid "${USER_GID}" "${XDESKTOP_USER}" \
    && printf 'BUILD_USER=%s\nBUILD_UID=%s\nBUILD_GID=%s\n' "${XDESKTOP_USER}" "${USER_UID}" "${USER_GID}" \
        > /etc/xdesktop/build.env \
    && echo "${XDESKTOP_USER}" > /etc/xdesktop/current-user

ENV DISPLAY=:1

EXPOSE 6080 5901

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --start-interval=3s --retries=3 \
    CMD ["/usr/local/bin/xdesktop-healthcheck"]

# Starts as root; entrypoint.sh drops privileges to the desktop user with setpriv.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
