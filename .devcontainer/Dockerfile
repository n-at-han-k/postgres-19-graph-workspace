ARG IMAGE_TAG=latest
FROM ghcr.io/lucernae/devcontainer-nix:${IMAGE_TAG}

# See https://aka.ms/vscode-remote/containers/non-root-user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG USER_HOME_DIR=/home/${USERNAME}

USER root

# Preload docker/docker-compose CLI wrappers into root's nix profile at build time,
# rather than at container runtime.
ADD devcontainer-overrides/root /root/devcontainer-overrides
RUN nix-env -if /root/devcontainer-overrides

ADD entrypoint-overrides.sh ${USER_HOME_DIR}/entrypoint-overrides.sh
RUN chmod +x ${USER_HOME_DIR}/entrypoint-overrides.sh \
    && chmod +x ${USER_HOME_DIR}/entrypoint.sh \
    && chmod u+s $(readlink -f $(command -v sudo)) \
    && chown ${USERNAME}:${USERNAME} /nix/store

# VS-Code patch so that devcontainer detects available shells
RUN echo "/nix/var/nix/profiles/default/bin/bash" >> /etc/shells \
    && echo "/nix/var/nix/profiles/default/bin/zsh" >> /etc/shells \
    && echo "/nix/var/nix/profiles/default/bin/nix-shell" >> /etc/shells
