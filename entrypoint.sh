#!/bin/sh
set -e

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# 1. Configure timezone
if [ -n "${TZ}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    echo "${TZ}" > /etc/timezone
    log "Timezone configured: ${TZ}"
fi

# 2. Direct execution if CLI arguments were passed (e.g. 'list', 'prune', '--help')
if [ $# -gt 0 ]; then
    exec /app/contabo_snapshot.sh "$@"
fi

# 3. Scheduled Daemon Mode vs One-shot Default
if [ -n "${CRON_SCHEDULE}" ]; then
    log "Starting Contabo Snapshot Manager daemon (Cron: '${CRON_SCHEDULE}')..."

    # Export container environment safely for crond sub-processes (POSIX-compliant shell export)
    export -p | grep -E ' (CONTABO_|CLIENT_|API_|MAX_|SNAPSHOT_|DRY_RUN|WAIT_AFTER_DELETE|INCLUDE_|EXCLUDE_|INSTANCE_|TZ)' > /etc/environment || true
    chmod 600 /etc/environment 2>/dev/null || true

    # Register cron job
    echo "${CRON_SCHEDULE} . /etc/environment; /app/contabo_snapshot.sh run >> /proc/1/fd/1 2>&1" > /etc/crontabs/root

    # Initial rotation on startup if requested
    if [ "${RUN_ON_STARTUP}" = "true" ] || [ "${RUN_ON_STARTUP}" = "1" ]; then
        log "Running initial snapshot rotation on startup (RUN_ON_STARTUP=true)..."
        /app/contabo_snapshot.sh run || true
    fi

    exec crond -f -l 2
else
    log "No CRON_SCHEDULE provided. Running one-shot rotation..."
    exec /app/contabo_snapshot.sh run
fi
