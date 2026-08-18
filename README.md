# 🔄 Contabo Snapshot Manager

[![CI & Lint](https://github.com/rgruenewald/contabo-snapshot-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/rgruenewald/contabo-snapshot-manager/actions/workflows/ci.yml)
[![Docker Multi-Arch](https://img.shields.io/badge/docker-multi--arch%20(amd64%2Farm64)-2496ED.svg?logo=docker&logoColor=white)](https://github.com/rgruenewald/contabo-snapshot-manager/pkgs/container/contabo-snapshot-manager)
[![Alpine Linux](https://img.shields.io/badge/alpine-3.21-0D597F.svg?logo=alpinelinux&logoColor=white)](https://alpinelinux.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Lightweight, reliable **Docker Ring-Buffer Snapshot Manager** for Contabo Cloud VPS & VDS instances (~15 MB Alpine image, Multi-Arch AMD64/ARM64) using the official Contabo REST API v1 directly.

Supports both automated **daemon mode (integrated cron)** and **one-shot / ad-hoc CLI executions**.

---

## ✨ Features

- 🔄 **True FIFO Ring-Buffer:** Retains $N$ snapshots per instance (`MAX_SNAPSHOTS=auto` or fixed number `1`–`4`). Oldest snapshots are only deleted when your quota is full.
- 🧠 **Smart Quota Detection (`auto`):** Automatically determines the snapshot limit of your VPS/VDS tier (e.g. VPS S=1, M=2, L=3, XL=4).
- 🐳 **Multi-Arch Docker Image:** Runs natively on `linux/amd64` (x86_64) and `linux/arm64` (Apple Silicon, Ampere, Raspberry Pi).
- 🧪 **Dry-Run Mode (`--dry-run`):** Safely simulate any operation without modifying snapshots.
- 🎯 **Instance Filtering:** Target specific instances (`INCLUDE_INSTANCES`), exclude instances (`EXCLUDE_INSTANCES`), or filter by name (`INSTANCE_FILTER`).
- 🛡️ **Zero External Dependencies:** 100% pure POSIX / Bash / Alpine implementation with no telemetry or third-party cloud connections.

---

## 🚀 Quick Start

### Option A: Using Pre-built Docker Image (Fastest)

1. Create a local `.env` file with your [Contabo API Credentials](https://my.contabo.com/api):

```bash
cat << "ENVEOF" > .env
CONTABO_CLIENT_ID="your-client-id"
CONTABO_CLIENT_SECRET="your-client-secret"
CONTABO_API_USER="your-email@domain.com"
CONTABO_API_PASSWORD="your-api-password"
ENVEOF
```

2. Start the background cron daemon:

```bash
docker run -d \
  --name contabo-snapshots \
  --restart unless-stopped \
  --env-file .env \
  ghcr.io/rgruenewald/contabo-snapshot-manager:latest
```

---

### Option B: Using Docker Compose

1. Clone the repository and copy the configuration:

```bash
git clone https://github.com/rgruenewald/contabo-snapshot-manager.git
cd contabo-snapshot-manager
cp .env.example .env
nano .env
```

2. Start the container in background daemon mode:

```bash
# Start background cron daemon (default: daily at 03:00)
docker compose up -d

# View live container logs
docker compose logs -f
```

---

## ⚙️ Environment Variables (`.env`)

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `CONTABO_CLIENT_ID` | **Yes** | — | Contabo API Client ID |
| `CONTABO_CLIENT_SECRET` | **Yes** | — | Contabo API Client Secret |
| `CONTABO_API_USER` | **Yes** | — | Contabo API Username / Email |
| `CONTABO_API_PASSWORD` | **Yes** | — | Contabo API Password |
| `MAX_SNAPSHOTS` | No | `auto` | Max snapshots per VPS (`auto` or `1`–`4`) |
| `SNAPSHOT_NAME` | No | `daily` | Prefix for automated snapshot names |
| `SNAPSHOT_DESCRIPTION`| No | `Automated...` | Metadata description for created snapshots |
| `INCLUDE_INSTANCES` | No | *(all)* | Comma-separated instance IDs (e.g. `1001,1002`) |
| `EXCLUDE_INSTANCES` | No | *(none)* | Comma-separated instance IDs to ignore |
| `INSTANCE_FILTER` | No | *(all)* | Substring filter on instance / display names |
| `DRY_RUN` | No | `false` | Simulate operations without API changes |
| `WAIT_AFTER_DELETE` | No | `5` | Delay in seconds after deletion before creation |
| `CRON_SCHEDULE` | No | `0 3 * * *` | Cron schedule expression for daemon mode |
| `RUN_ON_STARTUP` | No | `false` | Run an immediate rotation when starting container |
| `TZ` | No | `Europe/Berlin` | Timezone for logs and cron scheduler |

### ⏰ Cron Schedule Examples

| Expression | Schedule |
| :--- | :--- |
| `0 3 * * *` | Every day at 03:00 AM *(Default)* |
| `0 */12 * * *` | Every 12 hours (00:00 and 12:00) |
| `0 2 * * 0` | Every Sunday at 02:00 AM (Weekly) |
| `0 1 1 * *` | 1st day of every month at 01:00 AM (Monthly) |

---

## 💻 CLI & Ad-hoc Commands

You can run any management command on-demand inside the container:

```bash
# List all instances, tiers, quotas, and current snapshot counts
docker compose run --rm contabo-snapshots list

# Detailed view with snapshot IDs and creation dates
docker compose run --rm contabo-snapshots list-detailed

# Run snapshot rotation immediately (or simulate with --dry-run)
docker compose run --rm contabo-snapshots run
docker compose run --rm contabo-snapshots run --dry-run

# Prune excess snapshots to enforce quotas (no new snapshots created)
docker compose run --rm contabo-snapshots prune

# Filtered execution (e.g. only instances 1001,1002 or matching "prod")
docker compose run --rm contabo-snapshots list -f prod
docker compose run --rm contabo-snapshots run -i 1001,1002

# Manually create, delete, or rollback a snapshot
docker compose run --rm contabo-snapshots create <INST_ID> "pre-upgrade" "Before system upgrade"
docker compose run --rm contabo-snapshots delete <INST_ID> <SNAP_ID>
docker compose run --rm contabo-snapshots rollback <INST_ID> <SNAP_ID>
```

> **Tip:** If running standalone with Docker:
> ```bash
> docker run --rm --env-file .env ghcr.io/rgruenewald/contabo-snapshot-manager:latest list
> ```

---

## 🛡️ Security

- Credentials are read only from environment variables in memory and never stored in image layers.
- For vulnerability reports, please review our [Security Policy](SECURITY.md).

---

## 📄 License

MIT License - see [LICENSE](LICENSE).
