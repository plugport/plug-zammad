# Plug Zammad — thin wrapper around the upstream image.
# Per-role command (zammad-railsserver, zammad-websocket, zammad-scheduler,
# zammad-init, zammad-nginx) is set per Container App in
# evinyacp/az-0265-infra/infrastructure/apps.tf, not here.
ARG ZAMMAD_VERSION=7.0.1-0045
FROM ghcr.io/zammad/zammad:${ZAMMAD_VERSION}

LABEL org.opencontainers.image.title="plug-zammad" \
      org.opencontainers.image.source="https://github.com/plugport/plug-zammad" \
      org.opencontainers.image.vendor="Plug" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"
