#!/usr/bin/env bash

# Make the docker socket accessible to the non-root vscode user WITHOUT chowning
# it. The socket is bind-mounted from the host, so chowning it (as the upstream
# Codespaces sample does) would strip the host's own docker group of access.
# Instead, create a group inside the container matching the socket's GID and add
# vscode to it.
if [[ -S /var/run/docker.sock ]]; then
    SOCKET_GID=$(stat -c '%g' /var/run/docker.sock)
    if [[ "${SOCKET_GID}" != "0" ]]; then
        if ! getent group "${SOCKET_GID}" >/dev/null; then
            sudo groupadd --gid "${SOCKET_GID}" docker-host
        fi
        sudo usermod -aG "${SOCKET_GID}" vscode
    fi
fi

docker buildx install 2>/dev/null || true

# hand off to the base image entrypoint (starts nix-daemon, activates direnv)
cd /home/vscode && ./entrypoint.sh "${@:1}"
