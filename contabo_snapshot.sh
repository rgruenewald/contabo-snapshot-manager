#!/usr/bin/env bash
# ==============================================================================
# Contabo Snapshot Manager (Pure Docker Edition)
# Automated Ring-Buffer Snapshot Management using Contabo REST API v1
# ==============================================================================
set -eo pipefail

# Default settings from container environment
MAX_SNAPSHOTS="${MAX_SNAPSHOTS:-auto}"
SNAPSHOT_NAME="${SNAPSHOT_NAME:-daily}"
SNAPSHOT_DESCRIPTION="${SNAPSHOT_DESCRIPTION:-Automated snapshot by Contabo Snapshot Manager}"
DRY_RUN="${DRY_RUN:-false}"
WAIT_AFTER_DELETE="${WAIT_AFTER_DELETE:-5}"
INCLUDE_INSTANCES="${INCLUDE_INSTANCES:-}"
EXCLUDE_INSTANCES="${EXCLUDE_INSTANCES:-}"
INSTANCE_FILTER="${INSTANCE_FILTER:-}"

ACTION="run"
ARG_INSTANCE_ID=""
ARG_SNAPSHOT_ID=""
ARG_CUSTOM_NAME=""
ARG_CUSTOM_DESC=""

# Stats tracking
CREATED_COUNT=0
DELETED_COUNT=0
ERROR_COUNT=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

show_help() {
    cat << 'HELP'
Contabo Snapshot Manager (Docker Edition)
Automated Ring-Buffer Snapshot Management for Contabo Cloud VPS & VDS.

Usage:
  contabo_snapshot.sh [command] [options]

Commands:
  run                             Rotate ring-buffer and create new snapshot (default)
  list, --list                    List instances, quotas and snapshot counts
  list-detailed, --list-detailed  Show detailed list with individual snapshots
  prune, --prune                  Delete excess snapshots to enforce quotas (no creation)
  create <inst_id> [name] [desc]  Create a manual snapshot on an instance
  delete <inst_id> <snap_id>      Delete a specific snapshot
  rollback <inst_id> <snap_id>    Rollback an instance to a snapshot

Options:
  -m, --max-snapshots <N|auto>    Target retention limit per VPS (default: auto)
  -n, --name <prefix>             Snapshot name prefix (default: daily)
  -d, --desc <description>        Snapshot description text
  -i, --include <ids>             Comma-separated list of instance IDs to include
  -e, --exclude <ids>             Comma-separated list of instance IDs to exclude
  -f, --filter <string>           Filter instances by name / displayName substring
  -w, --wait <seconds>            Seconds to wait after snapshot deletion (default: 5)
  --dry-run                       Simulate operations without making API changes
  -h, --help                      Show this help message
HELP
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        run)
            ACTION="run"
            shift
            ;;
        list|--list)
            ACTION="list"
            shift
            ;;
        list-detailed|--list-detailed)
            ACTION="list_detailed"
            shift
            ;;
        prune|--prune)
            ACTION="prune"
            shift
            ;;
        create)
            ACTION="create"
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_INSTANCE_ID="$1"
                shift
            fi
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_CUSTOM_NAME="$1"
                shift
            fi
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_CUSTOM_DESC="$1"
                shift
            fi
            ;;
        delete)
            ACTION="delete"
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_INSTANCE_ID="$1"
                shift
            fi
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_SNAPSHOT_ID="$1"
                shift
            fi
            ;;
        rollback)
            ACTION="rollback"
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_INSTANCE_ID="$1"
                shift
            fi
            if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                ARG_SNAPSHOT_ID="$1"
                shift
            fi
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -m|--max-snapshots)
            if [[ $# -lt 2 || "$2" =~ ^- ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            MAX_SNAPSHOTS="$2"
            shift 2
            ;;
        -n|--name)
            if [[ $# -lt 2 || "$2" =~ ^- ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            SNAPSHOT_NAME="$2"
            shift 2
            ;;
        -d|--desc)
            if [[ $# -lt 2 ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            SNAPSHOT_DESCRIPTION="$2"
            shift 2
            ;;
        -i|--include)
            if [[ $# -lt 2 || "$2" =~ ^- ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            INCLUDE_INSTANCES="$2"
            shift 2
            ;;
        -e|--exclude)
            if [[ $# -lt 2 || "$2" =~ ^- ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            EXCLUDE_INSTANCES="$2"
            shift 2
            ;;
        -f|--filter)
            if [[ $# -lt 2 || "$2" =~ ^- ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            INSTANCE_FILTER="$2"
            shift 2
            ;;
        -w|--wait)
            if [[ $# -lt 2 || "$2" =~ ^- ]]; then
                log_err "Option '$1' requires an argument."
                exit 1
            fi
            WAIT_AFTER_DELETE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option/command: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Early validation of action-specific parameters
case "$ACTION" in
    create)
        if [ -z "$ARG_INSTANCE_ID" ]; then
            log_err "Missing instance ID. Usage: contabo_snapshot.sh create <instance_id> [name] [desc]"
            exit 1
        fi
        ;;
    delete)
        if [ -z "$ARG_INSTANCE_ID" ] || [ -z "$ARG_SNAPSHOT_ID" ]; then
            log_err "Missing parameters. Usage: contabo_snapshot.sh delete <instance_id> <snapshot_id>"
            exit 1
        fi
        ;;
    rollback)
        if [ -z "$ARG_INSTANCE_ID" ] || [ -z "$ARG_SNAPSHOT_ID" ]; then
            log_err "Missing parameters. Usage: contabo_snapshot.sh rollback <instance_id> <snapshot_id>"
            exit 1
        fi
        ;;
esac

# Validate MAX_SNAPSHOTS
if [ "$MAX_SNAPSHOTS" != "auto" ] && ! [[ "$MAX_SNAPSHOTS" =~ ^[0-9]+$ ]]; then
    log_err "Invalid MAX_SNAPSHOTS: '${MAX_SNAPSHOTS}'. Must be 'auto' or a positive integer (e.g. 1, 2, 3, 4)."
    exit 1
fi

# Validate WAIT_AFTER_DELETE
if ! [[ "$WAIT_AFTER_DELETE" =~ ^[0-9]+$ ]]; then
    log_err "Invalid WAIT_AFTER_DELETE: '${WAIT_AFTER_DELETE}'. Must be a non-negative integer (seconds)."
    exit 1
fi

# Normalize credentials supporting legacy aliases
CLIENT_ID="${CONTABO_CLIENT_ID:-${CLIENT_ID:-}}"
CLIENT_SECRET="${CONTABO_CLIENT_SECRET:-${CLIENT_SECRET:-}}"
API_USER="${CONTABO_API_USER:-${CONTABO_USER:-${API_USER:-}}}"
API_PASSWORD="${CONTABO_API_PASSWORD:-${CONTABO_PASSWORD:-${API_PASSWORD:-}}}"

# Validate Contabo credentials
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$API_USER" ] || [ -z "$API_PASSWORD" ]; then
    log_err "Missing Contabo API credentials!"
    log_err "Please set CONTABO_CLIENT_ID, CONTABO_CLIENT_SECRET, CONTABO_API_USER, CONTABO_API_PASSWORD in .env or container environment."
    exit 1
fi

# Helper: generate UUID for tracing
gen_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        od -x /dev/urandom 2>/dev/null | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}'
    fi
}

TRACE_ID=$(gen_uuid)
ACCESS_TOKEN=""
TOKEN_EXPIRES_IN=300
TOKEN_ACQUIRED_AT=0

# Authenticate with Contabo OAuth2 API
authenticate() {
    log "Authenticating with Contabo OAuth2 API..."
    local auth_response
    auth_response=$(curl -s -S --connect-timeout 15 --max-time 30 \
        -X POST "https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${CLIENT_ID}" \
        -d "client_secret=${CLIENT_SECRET}" \
        --data-urlencode "username=${API_USER}" \
        --data-urlencode "password=${API_PASSWORD}" \
        -d "grant_type=password")

    ACCESS_TOKEN=$(echo "$auth_response" | jq -r '.access_token // empty' 2>/dev/null || true)

    if [ -z "$ACCESS_TOKEN" ]; then
        local err_desc
        err_desc=$(echo "$auth_response" | jq -r '.error_description // .error // .message // empty' 2>/dev/null || true)
        log_err "Authentication failed!"
        if [ -n "$err_desc" ]; then
            log_err "Reason: ${err_desc}"
        else
            log_err "Server response: ${auth_response}"
        fi
        exit 1
    fi

    TOKEN_EXPIRES_IN=$(echo "$auth_response" | jq -r '.expires_in // 300' 2>/dev/null || echo 300)
    TOKEN_ACQUIRED_AT=$(date +%s)
    log "Authentication successful (token valid for ${TOKEN_EXPIRES_IN}s)."
}

# Ensure token is valid and refresh if close to expiration
ensure_auth() {
    if [ -z "$ACCESS_TOKEN" ]; then
        authenticate
        return
    fi
    local now
    now=$(date +%s)
    local age=$(( now - TOKEN_ACQUIRED_AT ))
    local buffer=30
    if [ "$age" -ge $(( TOKEN_EXPIRES_IN - buffer )) ]; then
        log "Access token expiring soon, re-authenticating..."
        authenticate
    fi
}

# Initial authentication
authenticate

# Helper function for Contabo API requests
api_call() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local req_id
    req_id=$(gen_uuid)

    ensure_auth

    local -a curl_opts=(
        -s -S
        --connect-timeout 15
        --max-time 60
        -X "$method"
        "https://api.contabo.com/v1${path}"
        -H "Authorization: Bearer ${ACCESS_TOKEN}"
        -H "Content-Type: application/json"
        -H "x-request-id: ${req_id}"
        -H "x-trace-id: ${TRACE_ID}"
    )

    if [ -n "$data" ]; then
        curl "${curl_opts[@]}" -d "$data"
    else
        curl "${curl_opts[@]}"
    fi
}

# Resolve snapshot limit for a VPS tier
get_instance_limit() {
    local product_size="$1"
    if [[ "$MAX_SNAPSHOTS" =~ ^[0-9]+$ ]]; then
        echo "$MAX_SNAPSHOTS"
        return
    fi
    # Auto detection based on Contabo tiers
    local upper_size
    upper_size=$(echo "$product_size" | tr '[:lower:]' '[:upper:]')
    if [[ "$upper_size" =~ XXL|MAX|XL|V80|V90|EXTRA.?LARGE ]]; then
        echo 4
    elif [[ "$upper_size" =~ (^|[^A-Z0-9])(L|LARGE|V60|V70)($|[^A-Z0-9]) ]]; then
        echo 3
    elif [[ "$upper_size" =~ (^|[^A-Z0-9])(M|MEDIUM|V40|V50)($|[^A-Z0-9]) ]]; then
        echo 2
    elif [[ "$upper_size" =~ VDS ]]; then
        echo 3
    else
        echo 1
    fi
}

# Fetch all compute instances handling pagination
fetch_all_instances() {
    local page=1
    local total_pages=1
    local all_data="[]"

    while [ "$page" -le "$total_pages" ]; do
        local resp
        resp=$(api_call "GET" "/compute/instances?page=${page}&size=100")
        
        # Check if response is valid JSON
        if ! echo "$resp" | jq -e . >/dev/null 2>&1; then
            log_err "Contabo API returned non-JSON response (HTTP error or maintenance). Response: ${resp:0:200}"
            return 1
        fi

        local page_data
        page_data=$(echo "$resp" | jq '.data // empty' 2>/dev/null || true)
        if [ -z "$page_data" ] || [ "$page_data" = "null" ]; then
            local err_msg
            err_msg=$(echo "$resp" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
            if [ -n "$err_msg" ]; then
                log_err "Contabo API error fetching instances: ${err_msg}"
            else
                log_err "Failed to fetch instances. API response: ${resp}"
            fi
            return 1
        fi

        all_data=$(jq -n --argjson a "$all_data" --argjson b "$page_data" '$a + $b')
        total_pages=$(echo "$resp" | jq -r '._pagination.totalPages // 1' 2>/dev/null || echo 1)
        page=$(( page + 1 ))
    done

    jq -n --argjson data "$all_data" '{data: $data}'
}

# --- Action: Single manual create ---
if [ "$ACTION" = "create" ]; then
    NAME="${ARG_CUSTOM_NAME:-manual-$(date +%Y%m%d-%H%M%S)}"
    DESC="${ARG_CUSTOM_DESC:-Manual snapshot}"
    if [ "$DRY_RUN" = "true" ]; then
        log "[Dry-Run] Would create snapshot '${NAME}' on instance ${ARG_INSTANCE_ID} (Desc: '${DESC}')"
        exit 0
    fi
    log "Creating snapshot '${NAME}' on instance ${ARG_INSTANCE_ID}..."
    PAYLOAD=$(jq -n --arg name "$NAME" --arg desc "$DESC" '{name: $name, description: $desc}')
    RESP=$(api_call "POST" "/compute/instances/${ARG_INSTANCE_ID}/snapshots" "$PAYLOAD")
    NEW_ID=$(echo "$RESP" | jq -r '.data[0].snapshotId // empty' 2>/dev/null || true)
    if [ -n "$NEW_ID" ]; then
        log "SUCCESS: Snapshot '${NAME}' created with ID: ${NEW_ID}"
        exit 0
    else
        ERR_MSG=$(echo "$RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
        if [ -n "$ERR_MSG" ]; then
            log_err "Failed to create snapshot: ${ERR_MSG}"
        else
            log_err "Failed to create snapshot: ${RESP}"
        fi
        exit 1
    fi
fi

# --- Action: Single manual delete ---
if [ "$ACTION" = "delete" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        log "[Dry-Run] Would delete snapshot ${ARG_SNAPSHOT_ID} from instance ${ARG_INSTANCE_ID}"
        exit 0
    fi
    log "Deleting snapshot ${ARG_SNAPSHOT_ID} from instance ${ARG_INSTANCE_ID}..."
    RESP=$(api_call "DELETE" "/compute/instances/${ARG_INSTANCE_ID}/snapshots/${ARG_SNAPSHOT_ID}")
    ERR_MSG=$(echo "$RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
    if [ -n "$ERR_MSG" ]; then
        log_err "Failed to delete snapshot: ${ERR_MSG}"
        exit 1
    fi
    log "Snapshot deletion completed successfully."
    exit 0
fi

# --- Action: Rollback ---
if [ "$ACTION" = "rollback" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        log "[Dry-Run] Would rollback instance ${ARG_INSTANCE_ID} to snapshot ${ARG_SNAPSHOT_ID}"
        exit 0
    fi
    log "Initiating rollback of instance ${ARG_INSTANCE_ID} to snapshot ${ARG_SNAPSHOT_ID}..."
    RESP=$(api_call "POST" "/compute/instances/${ARG_INSTANCE_ID}/snapshots/${ARG_SNAPSHOT_ID}/actions/rollback" "{}")
    ERR_MSG=$(echo "$RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
    if [ -n "$ERR_MSG" ]; then
        log_err "Failed to rollback instance: ${ERR_MSG}"
        exit 1
    fi
    log "Rollback command sent. The instance may take several minutes to apply."
    exit 0
fi

# --- Fetch instances list for batch actions ---
log "Fetching compute instances..."
RAW_INSTANCES_JSON=$(fetch_all_instances)
if [ -z "$RAW_INSTANCES_JSON" ] || ! echo "$RAW_INSTANCES_JSON" | jq -e . >/dev/null 2>&1; then
    log_err "Failed to fetch compute instances from Contabo API. Exiting."
    exit 1
fi

# Apply filters: INCLUDE_INSTANCES, EXCLUDE_INSTANCES, INSTANCE_FILTER
INSTANCES_JSON=$(echo "$RAW_INSTANCES_JSON" | jq \
    --arg include "${INCLUDE_INSTANCES:-}" \
    --arg exclude "${EXCLUDE_INSTANCES:-}" \
    --arg filter "${INSTANCE_FILTER:-}" '
    .data as $items |
    if $items == null then . else
      .data = ($items |
        (if ($include | length > 0) then
           ($include | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "") | tonumber? // .)) as $inc |
           map(select(.instanceId as $id | ($inc | index($id)) != null or ($inc | index($id|tostring)) != null))
         else . end) |
        (if ($exclude | length > 0) then
           ($exclude | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "") | tonumber? // .)) as $exc |
           map(select(.instanceId as $id | (($exc | index($id)) == null and ($exc | index($id|tostring)) == null)))
         else . end) |
        (if ($filter | length > 0) then
           ($filter | ascii_downcase) as $f |
           map(select(((.displayName // "") + " " + (.name // "")) | ascii_downcase | contains($f)))
         else . end)
      )
    end
')

INSTANCE_IDS=$(echo "$INSTANCES_JSON" | jq -r '.data[]?.instanceId // empty')

if [ -z "$INSTANCE_IDS" ]; then
    TOTAL_COUNT=$(echo "$RAW_INSTANCES_JSON" | jq -r '.data | length // 0')
    log "No matching compute instances found (Total unfiltered: ${TOTAL_COUNT})."
    exit 0
fi

# --- Action: List / List-Detailed ---
if [ "$ACTION" = "list" ] || [ "$ACTION" = "list_detailed" ]; then
    printf "\n%-12s %-25s %-10s %-12s %-12s %-15s\n" "INSTANCE ID" "DISPLAY NAME" "STATUS" "SIZE" "QUOTA" "SNAPSHOTS"
    printf "%-12s %-25s %-10s %-12s %-12s %-15s\n" "-----------" "-------------------------" "----------" "------------" "------------" "---------------"
    for INSTANCE_ID in $INSTANCE_IDS; do
        INST_NAME=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .displayName // .name // $id')
        STATUS=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .status // "-"')
        SIZE=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .productSize // .productType // "-"')
        LIMIT=$(get_instance_limit "$SIZE")

        SNAPS_JSON=$(api_call "GET" "/compute/instances/${INSTANCE_ID}/snapshots")
        SNAPS_ERR=$(echo "$SNAPS_JSON" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
        if [ -n "$SNAPS_ERR" ]; then
            printf "%-12s %-25s %-10s %-12s %-12s %-15s\n" "$INSTANCE_ID" "${INST_NAME:0:24}" "$STATUS" "$SIZE" "?/${LIMIT}" "Error: ${SNAPS_ERR}"
            continue
        fi

        COUNT=$(echo "$SNAPS_JSON" | jq -r '.data | length // 0' 2>/dev/null || echo 0)
        printf "%-12s %-25s %-10s %-12s %-12s %-15s\n" "$INSTANCE_ID" "${INST_NAME:0:24}" "$STATUS" "$SIZE" "${COUNT}/${LIMIT}" "${COUNT} snapshot(s)"

        if [ "$ACTION" = "list_detailed" ] && [ "$COUNT" -gt 0 ]; then
            echo "$SNAPS_JSON" | jq -r '.data[] | "    -> ID: " + (.snapshotId|tostring) + " | Name: " + (.name // "-") + " | Created: " + (.createdDate // "-") + " | Auto-Delete: " + (.autoDeleteDate // "-")'
        fi
    done
    echo ""
    exit 0
fi

# --- Action: Prune only (without creation) ---
if [ "$ACTION" = "prune" ]; then
    log "=== Starting Snapshot Pruning (Enforce Quotas) [Dry-Run: ${DRY_RUN}] ==="
    for INSTANCE_ID in $INSTANCE_IDS; do
        INST_NAME=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .displayName // .name // $id')
        PRODUCT_SIZE=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .productSize // .productType // ""')
        LIMIT=$(get_instance_limit "$PRODUCT_SIZE")

        SNAPS_RESP=$(api_call "GET" "/compute/instances/${INSTANCE_ID}/snapshots")
        SNAPS_ERR=$(echo "$SNAPS_RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
        if [ -n "$SNAPS_ERR" ]; then
            log_err "Instance ${INST_NAME}: Failed to fetch snapshots: ${SNAPS_ERR}"
            ERROR_COUNT=$(( ERROR_COUNT + 1 ))
            continue
        fi

        SORTED_SNAPS=$(echo "$SNAPS_RESP" | jq -r '.data // [] | sort_by(.createdDate)')
        CURRENT_COUNT=$(echo "$SORTED_SNAPS" | jq -r 'length // 0')

        if [ "$CURRENT_COUNT" -gt "$LIMIT" ]; then
            EXCESS=$(( CURRENT_COUNT - LIMIT ))
            log "Instance ${INST_NAME}: Pruning ${EXCESS} excess snapshot(s) (Current: ${CURRENT_COUNT}, Quota: ${LIMIT})..."
            OLDEST_IDS=$(echo "$SORTED_SNAPS" | jq -r ".[0:${EXCESS}][].snapshotId // empty")
            for SNAP_ID in $OLDEST_IDS; do
                SNAP_NAME=$(echo "$SORTED_SNAPS" | jq -r --arg sid "$SNAP_ID" '.[] | select(.snapshotId == $sid) | .name // "unknown"')
                if [ "$DRY_RUN" = "true" ]; then
                    log "[Dry-Run] Would prune snapshot '${SNAP_NAME}' (ID: ${SNAP_ID})"
                    DELETED_COUNT=$(( DELETED_COUNT + 1 ))
                else
                    log "Pruning snapshot '${SNAP_NAME}' (ID: ${SNAP_ID})..."
                    DEL_RESP=$(api_call "DELETE" "/compute/instances/${INSTANCE_ID}/snapshots/${SNAP_ID}")
                    DEL_ERR=$(echo "$DEL_RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
                    if [ -n "$DEL_ERR" ]; then
                        log_err "Failed to prune snapshot '${SNAP_NAME}' (ID: ${SNAP_ID}): ${DEL_ERR}"
                        ERROR_COUNT=$(( ERROR_COUNT + 1 ))
                    else
                        DELETED_COUNT=$(( DELETED_COUNT + 1 ))
                        log "Snapshot '${SNAP_NAME}' pruned successfully."
                    fi
                    if [ "$WAIT_AFTER_DELETE" -gt 0 ]; then
                        sleep "$WAIT_AFTER_DELETE"
                    fi
                fi
            done
        else
            log "Instance ${INST_NAME}: No excess snapshots (${CURRENT_COUNT}/${LIMIT})."
        fi
    done
    log "============================================================"
    log "=== Pruning Finished: ${DELETED_COUNT} deleted, ${ERROR_COUNT} errors ==="
    if [ "$ERROR_COUNT" -gt 0 ]; then
        exit 1
    fi
    exit 0
fi

# --- Action: Run (Full Ring Buffer Rotation) ---
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
NEW_SNAP_NAME="${SNAPSHOT_NAME}-${TIMESTAMP}"

log "=== Starting Snapshot Ring-Buffer Rotation [Dry-Run: ${DRY_RUN}] ==="

for INSTANCE_ID in $INSTANCE_IDS; do
    INST_NAME=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .displayName // .name // $id')
    PRODUCT_SIZE=$(echo "$INSTANCES_JSON" | jq -r --arg id "$INSTANCE_ID" '.data[] | select((.instanceId|tostring) == $id) | .productSize // .productType // ""')
    LIMIT=$(get_instance_limit "$PRODUCT_SIZE")

    log "------------------------------------------------------------"
    log "Instance: ${INST_NAME} (ID: ${INSTANCE_ID}, Tier: ${PRODUCT_SIZE:-Standard}, Quota: ${LIMIT})"

    # Fetch snapshots sorted chronologically by createdDate ascending
    SNAPS_RESP=$(api_call "GET" "/compute/instances/${INSTANCE_ID}/snapshots")
    SNAPS_ERR=$(echo "$SNAPS_RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
    if [ -n "$SNAPS_ERR" ]; then
        log_err "Failed to fetch snapshots for instance ${INST_NAME}: ${SNAPS_ERR}"
        ERROR_COUNT=$(( ERROR_COUNT + 1 ))
        continue
    fi

    SORTED_SNAPS=$(echo "$SNAPS_RESP" | jq -r '.data // [] | sort_by(.createdDate)')
    CURRENT_COUNT=$(echo "$SORTED_SNAPS" | jq -r 'length // 0')

    log "Current snapshots: ${CURRENT_COUNT} of max ${LIMIT}"

    # Ring Buffer Logic:
    # If at or above limit, delete the oldest (CURRENT_COUNT - LIMIT + 1) to make room
    DELETE_FAILED=false
    if [ "$CURRENT_COUNT" -ge "$LIMIT" ]; then
        TO_DELETE_COUNT=$(( CURRENT_COUNT - LIMIT + 1 ))
        log "Quota reached: Deleting ${TO_DELETE_COUNT} oldest snapshot(s) to free up slot..."

        OLDEST_IDS=$(echo "$SORTED_SNAPS" | jq -r ".[0:${TO_DELETE_COUNT}][].snapshotId // empty")

        for SNAP_ID in $OLDEST_IDS; do
            SNAP_NAME=$(echo "$SORTED_SNAPS" | jq -r --arg sid "$SNAP_ID" '.[] | select(.snapshotId == $sid) | .name // "unknown"')
            if [ "$DRY_RUN" = "true" ]; then
                log "[Dry-Run] Would delete oldest snapshot '${SNAP_NAME}' (ID: ${SNAP_ID})"
                DELETED_COUNT=$(( DELETED_COUNT + 1 ))
            else
                log "Deleting oldest snapshot '${SNAP_NAME}' (ID: ${SNAP_ID})..."
                DEL_RESP=$(api_call "DELETE" "/compute/instances/${INSTANCE_ID}/snapshots/${SNAP_ID}")
                DEL_ERR=$(echo "$DEL_RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
                if [ -n "$DEL_ERR" ]; then
                    log_err "Failed to delete snapshot '${SNAP_NAME}' (ID: ${SNAP_ID}): ${DEL_ERR}"
                    ERROR_COUNT=$(( ERROR_COUNT + 1 ))
                    DELETE_FAILED=true
                else
                    log "Snapshot '${SNAP_NAME}' deleted successfully."
                    DELETED_COUNT=$(( DELETED_COUNT + 1 ))
                fi
                if [ "$WAIT_AFTER_DELETE" -gt 0 ]; then
                    sleep "$WAIT_AFTER_DELETE"
                fi
            fi
        done
    else
        log "Slot available (${CURRENT_COUNT}/${LIMIT}). No deletion needed."
    fi

    # If deletion failed and quota was exceeded, skip creation to avoid predictable quota error
    if [ "$DELETE_FAILED" = "true" ]; then
        log_err "Skipping snapshot creation on instance ${INST_NAME} due to deletion failure."
        continue
    fi

    # Create new snapshot
    if [ "$DRY_RUN" = "true" ]; then
        log "[Dry-Run] Would create snapshot '${NEW_SNAP_NAME}' on instance ${INSTANCE_ID}"
        CREATED_COUNT=$(( CREATED_COUNT + 1 ))
    else
        log "Creating new snapshot '${NEW_SNAP_NAME}' on instance ${INSTANCE_ID}..."
        PAYLOAD=$(jq -n --arg name "$NEW_SNAP_NAME" --arg desc "$SNAPSHOT_DESCRIPTION" '{name: $name, description: $desc}')
        CREATE_RESP=$(api_call "POST" "/compute/instances/${INSTANCE_ID}/snapshots" "$PAYLOAD")
        
        NEW_ID=$(echo "$CREATE_RESP" | jq -r '.data[0].snapshotId // empty' 2>/dev/null || true)
        if [ -n "$NEW_ID" ]; then
            log "SUCCESS: Created snapshot '${NEW_SNAP_NAME}' (ID: ${NEW_ID})"
            CREATED_COUNT=$(( CREATED_COUNT + 1 ))
        else
            CREATE_ERR=$(echo "$CREATE_RESP" | jq -r '.message // .errors[0].message // empty' 2>/dev/null || true)
            if [ -n "$CREATE_ERR" ]; then
                log_err "Failed to create snapshot on instance ${INSTANCE_ID}: ${CREATE_ERR}"
            else
                log_err "Failed to create snapshot on instance ${INSTANCE_ID}: ${CREATE_RESP}"
            fi
            ERROR_COUNT=$(( ERROR_COUNT + 1 ))
        fi
    fi
done

log "============================================================"
log "=== Rotation Finished: ${CREATED_COUNT} created, ${DELETED_COUNT} deleted, ${ERROR_COUNT} errors ==="

if [ "$ERROR_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
