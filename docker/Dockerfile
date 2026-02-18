# Dockerfile with SteamRT3
FROM        registry.gitlab.steamos.cloud/steamrt/sniper/platform:latest-container-runtime-depot
LABEL       author="Miksen" \
            maintainer="mikkel@pwnt.dk" \
            org.opencontainers.image.description="CS2 Pterodactyl Egg" \
            org.opencontainers.image.source="https://github.com/mrc4tt/CS2-Egg"

# Prep OS
RUN         mkdir -p /etc/sudoers.d && \
            echo "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/flatdeb && \
            chmod 0440 /etc/sudoers.d/flatdeb

ENV         DEBIAN_FRONTEND=noninteractive
RUN         apt update && \
            apt install -y iproute2 jq unzip expect rsync && \
            apt-get clean

RUN         mkdir -p /scripts /utils
COPY        ./scripts/* /scripts/
COPY        ./utils/* /utils/
COPY        ./entrypoint.sh /entrypoint.sh

RUN         chmod 555 /scripts/*.sh && \
            chmod 555 /utils/*.sh && \
            chmod 555 /entrypoint.sh

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

CMD         [ "/bin/bash", "/entrypoint.sh" ]
