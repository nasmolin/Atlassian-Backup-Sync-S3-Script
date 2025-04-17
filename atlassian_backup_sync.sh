#!/bin/bash

set -eo pipefail

# CHANGE_ME USERS_MENTION=""
# CHANGE_ME TELEGRAM_WEBHOOK_URL=""
# CHANGE_ME TELEGRAM_CHAT_ID=""
# CHANGE_ME RETENTION_DAYS=7
# CHANGE_ME S3_BUCKET_NAME=""

SERVICE_TYPE="${1:-jira}"
HOSTNAME=$(hostname -f)
CRON_SOURCE=$(grep -F "$0" /var/spool/cron/crontabs/root 2>/dev/null || echo "N/A")
LOG_TAIL=$(mktemp)

if [[ "$SERVICE_TYPE" == "confluence" ]]; then
    BACKUP_DIR="/var/atlassian/application-data/confluence/backups"
    TMP_DIR="/tmp/confluence_backup_check"
    S3_BUCKET="s3://${S3_BUCKET_NAME}/confluence-zip-backups"
    LOG="/var/log/confluence-backup-sync.log"
    FILE_PATTERN="backup.*.zip"
    S3_DATE_REGEX='backup\.\K\d{4}-\d{2}-\d{2}'
else
    BACKUP_DIR="/var/atlassian/application-data/jira/export"
    TMP_DIR="/tmp/jira_backup_check"
    S3_BUCKET="s3://${S3_BUCKET_NAME}/jira-xml-backups"
    LOG="/var/log/jira-backup-sync.log"
    FILE_PATTERN="*.zip"
    S3_DATE_REGEX='\d{4}-\d{2}-\d{2}'
fi

mkdir -p "$TMP_DIR"
exec >> "$LOG" 2>&1

STATUS="SUCCESS"
MESSAGE="${SERVICE_TYPE} backup job completed successfully"

log() {
    local level="$1"
    local message="$2"
    echo "[$level] $message"
}

notify_telegram() {
    local level="$1"
    local message="$2"
    local mention=""
    if [[ "$level" == "ERROR" ]]; then
        mention="$USERS_MENTION"
    fi

    local formatted_message="
Users mention: $mention
Server: $HOSTNAME
Source: $CRON_SOURCE
Message: [$level] $message"

    tail -n 3 "$LOG" > "$LOG_TAIL"

    curl -s -X POST "$TELEGRAM_WEBHOOK_URL" \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        -F "caption=$formatted_message" \
        -F "document=@$LOG_TAIL" > /dev/null
}

cleanup() {
    if [[ "$STATUS" == "ERROR" ]]; then
        notify_telegram "ERROR" "$MESSAGE"
    else
        notify_telegram "SUCCESS" "$MESSAGE"
    fi
    rm -rf "$TMP_DIR"
    rm -f "$LOG_TAIL"
}
trap cleanup EXIT
trap 'STATUS="ERROR"; MESSAGE="Unexpected error on line $LINENO"' ERR

log "INFO" "${SERVICE_TYPE}-backup-to-s3 job started"

latest_backup=$(find "$BACKUP_DIR" -type f -name "$FILE_PATTERN" -printf "%T@ %p\n" | sort -n | tail -1 | awk '{print $2}')

if [[ -z "$latest_backup" ]]; then
    STATUS="ERROR"
    MESSAGE="No .zip file found in $BACKUP_DIR"
    log "ERROR" "$MESSAGE"
    exit 1
fi

log "INFO" "Found latest backup file: $latest_backup"

if ! unzip -q -o "$latest_backup" "entities.xml" -d "$TMP_DIR"; then
    STATUS="ERROR"
    MESSAGE="Failed to unzip entities.xml from $latest_backup"
    log "ERROR" "$MESSAGE"
    exit 1
fi

if [[ ! -s "$TMP_DIR/entities.xml" ]]; then
    STATUS="ERROR"
    MESSAGE="entities.xml is missing or empty in $latest_backup"
    log "ERROR" "$MESSAGE"
    exit 1
fi

log "INFO" "entities.xml exists and is not empty"

if aws s3 cp "$latest_backup" "$S3_BUCKET/"; then
    log "SUCCESS" "Backup uploaded to S3: $latest_backup"
else
    STATUS="ERROR"
    MESSAGE="Failed to upload $latest_backup to $S3_BUCKET"
    log "ERROR" "$MESSAGE"
    exit 1
fi

find "$BACKUP_DIR" -type f -name "*.zip" -mtime +$RETENTION_DAYS -exec rm -f {} \;
log "INFO" "Old local backups removed (older than $RETENTION_DAYS days)"

aws s3 ls "$S3_BUCKET/" | while read -r _ _ _ file; do
    file_date=$(echo "$file" | grep -oP "$S3_DATE_REGEX" | head -1)
    if [[ -n "$file_date" ]]; then
        file_timestamp=$(date -d "$file_date" +%s 2>/dev/null || echo 0)
        now=$(date +%s)
        diff_days=$(( (now - file_timestamp) / 86400 ))
        if (( diff_days > RETENTION_DAYS )); then
            aws s3 rm "$S3_BUCKET/$file"
            log "INFO" "Deleted old backup from S3: $file"
        fi
    fi
done

log "SUCCESS" "$MESSAGE"
