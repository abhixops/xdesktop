FROM ubuntu:24.04
LABEL maintainer="github.com/abhixops"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Build arguments for customizable non-root user
ARG USERNAME=xdesktop
ARG USER_UID=1000
ARG USER_GID=1000

# Install core utilities, prerequisites, and software management tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    gpg \
    software-properties-common \
    apt-transport-https \
    wget \
    sudo \
    locales \
    language-pack-en \
    && rm -rf /var/lib/apt/lists/*

# Configure Mozilla PPA to install native Firefox deb package instead of snap
COPY src/firefox-installation.sh /opt/firefox-installation.sh
RUN bash /opt/firefox-installation.sh \
    && add-apt-repository -y ppa:mozillateam/ppa \
    && rm -f /opt/firefox-installation.sh

# Configure Microsoft repository for Visual Studio Code
COPY src/vscode-repo.sh /opt/vscode-repo.sh
RUN bash /opt/vscode-repo.sh \
    && rm -f /opt/vscode-repo.sh

# Install desktop environment (XFCE), VNC/noVNC stack, VS Code, Firefox, and development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    tightvncserver \
    xfonts-base \
    xfonts-75dpi \
    xfonts-100dpi \
    xfonts-scalable \
    xauth \
    xterm \
    novnc \
    websockify \
    openssl \
    dbus-x11 \
    x11-xserver-utils \
    firefox \
    code \
    git \
    tmux \
    vim \
    nano \
    python3 \
    python3-pip \
    python3-cairo \
    alacarte \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && chown root:root /usr/share/code/chrome-sandbox \
    && chmod 4755 /usr/share/code/chrome-sandbox \
    && mv /usr/share/code/code /usr/share/code/code.bin \
    && printf '#!/bin/bash\nexec /usr/share/code/code.bin --no-sandbox "$@"\n' > /usr/share/code/code \
    && chmod +x /usr/share/code/code \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Custom desktop wallpaper
COPY assets/bg-l2.png /usr/share/backgrounds/xfce/xfce-custom.png
RUN ln -sf /usr/share/backgrounds/xfce/xfce-custom.png /usr/share/backgrounds/xfce/xfce-verticals.png \
    && ln -sf /usr/share/backgrounds/xfce/xfce-custom.png /usr/share/backgrounds/xfce/xfce-stripes.png \
    && ln -sf /usr/share/backgrounds/xfce/xfce-custom.png /usr/share/backgrounds/xfce/xfce-blue.jpg \
    && ln -sf /usr/share/backgrounds/xfce/xfce-custom.png /usr/share/backgrounds/xfce/xfce-teal.jpg

# Create non-root user and grant passwordless sudo privileges securely
# Ubuntu 24.04 includes a default 'ubuntu' user with UID/GID 1000; remove/replace if needed
RUN if id -u ${USER_UID} >/dev/null 2>&1; then \
        EXISTING_USER=$(id -nu ${USER_UID}); \
        if [ "$EXISTING_USER" != "${USERNAME}" ]; then \
            userdel -f -r "$EXISTING_USER" 2>/dev/null || true; \
        fi; \
    fi \
    && if getent group ${USER_GID} >/dev/null 2>&1; then \
        EXISTING_GROUP=$(getent group ${USER_GID} | cut -d: -f1); \
        if [ "$EXISTING_GROUP" != "${USERNAME}" ]; then \
            groupdel "$EXISTING_GROUP" 2>/dev/null || true; \
        fi; \
    fi \
    && if ! id -u ${USERNAME} >/dev/null 2>&1; then \
        groupadd --gid ${USER_GID} ${USERNAME} 2>/dev/null || true; \
        useradd -m -s /bin/bash -u ${USER_UID} -g ${USER_GID} ${USERNAME}; \
    fi \
    && mkdir -p /etc/sudoers.d \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Install X startup configuration and runtime entrypoint script
COPY src/xstartup /etc/skel/.vnc/xstartup
COPY src/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /home/${USERNAME}/.vnc \
    && cp /etc/skel/.vnc/xstartup /home/${USERNAME}/.vnc/xstartup \
    && chmod +x /home/${USERNAME}/.vnc/xstartup \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

# Set non-root user and execution environment
USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENV USER=${USERNAME}
ENV HOME=/home/${USERNAME}
ENV DISPLAY=:1

EXPOSE 5901
EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
