# Atlassian Backup Sync (S3) Script

This script uploads the latest Jira or Confluence backups to S3, checks integrity (`entities.xml`), cleans up outdated files both locally and in the cloud, and sends notifications to Telegram.

## Supported Services

It is assumed that scheduled backups are already configured.
- **Confluence** – can be configured in `Settings -> Configuration -> Backup Administration`:
    - Backup File Prefix - `backup.`
    - Backup File Date Pattern - `YYYY-MM-DD_HH-MM`
    - Backup Path - `/var/atlassian/application-data/confluence/backups`
- **Jira** – can be configured in `Settings -> Advanced -> Services -> Backup Service`:
    - Date format: `YYYY-MM-DD_HH-MM`
    - (opt) Schedule: `Daily`
    - (opt) Interval: `once per day`

## Usage

```bash
/usr/local/bin/atlassian_backup_sync.sh [jira|confluence]
```

## Variables
```bash
$RETENTION_DAYS="The script deletes archives older than this number of days (locally and in S3)"
$USERS_MENTION="Usernames to mention in the Telegram channel if the script fails"
$TELEGRAM_WEBHOOK_URL="Webhook in the format https://api.telegram.org/bot.../sendDocument"
$TELEGRAM_CHAT_ID="Telegram chat ID"
$S3_BUCKET_NAME="S3 bucket name"
```

## Storage and Paths

| Service Type | Local Path	                                              | S3 Bucket	                                                 | Log File                             |
|-------------|-------------------------------------------------------------|-----------------------------------------------------------|--------------------------------------|
| Jira        | `/var/atlassian/application-data/jira/export`              | `s3://${S3_BUCKET_NAME}/jira-xml-backups`             | `/var/log/jira-backup-sync.log`      |
| Confluence  | `/var/atlassian/application-data/confluence/backups`       | `s3://${S3_BUCKET_NAME}/confluence-zip-backups`       | `/var/log/confluence-backup-sync.log` |

