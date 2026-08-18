# Ultra-lightweight Multi-Arch Alpine Image (AMD64 + ARM64)
FROM alpine:3.21

LABEL maintainer="Ronny Gruenewald <https://github.com/rgruenewald>"
LABEL org.opencontainers.image.source="https://github.com/rgruenewald/contabo-snapshot-manager"
LABEL org.opencontainers.image.description="Contabo Snapshot Manager - Automated Ring-Buffer Pure Bash Edition"
LABEL org.opencontainers.image.licenses="MIT"

# Install bash, curl, jq, tzdata, ca-certificates
RUN apk add --no-cache bash curl jq tzdata ca-certificates

WORKDIR /app

COPY contabo_snapshot.sh /app/contabo_snapshot.sh
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/contabo_snapshot.sh /app/entrypoint.sh

# Default environment configuration
ENV CONTABO_CLIENT_ID="" \
    CONTABO_CLIENT_SECRET="" \
    CONTABO_API_USER="" \
    CONTABO_API_PASSWORD="" \
    MAX_SNAPSHOTS="auto" \
    SNAPSHOT_NAME="daily" \
    SNAPSHOT_DESCRIPTION="Automated ring-buffer snapshot" \
    DRY_RUN="false" \
    WAIT_AFTER_DELETE="5" \
    INCLUDE_INSTANCES="" \
    EXCLUDE_INSTANCES="" \
    INSTANCE_FILTER="" \
    CRON_SCHEDULE="0 3 * * *" \
    RUN_ON_STARTUP="false" \
    TZ="Europe/Berlin"

# Container Health Check (verifies crond is running in daemon mode)
HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=3 \
  CMD pgrep crond > /dev/null || [ -z "$CRON_SCHEDULE" ]

ENTRYPOINT ["/app/entrypoint.sh"]
