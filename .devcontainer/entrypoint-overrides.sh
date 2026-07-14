#!/usr/bin/env bash

# make docker socket accessible to the non-root vscode user
sudo chown root:vscode /var/run/docker.sock
docker buildx install

# hand off to the base image entrypoint (starts nix-daemon, activates direnv)
./entrypoint.sh "${@:1}"
