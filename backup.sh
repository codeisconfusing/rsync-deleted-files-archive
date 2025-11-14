#!/bin/bash

# Archive-based backup script with time-based retention
# Similar to bvckup2's recycle bin functionality for Linux

SOURCE_PATH="/home/username/"
BACKUP_PATH="/mnt/backup-drive/backup/"
ARCHIVE_PATH="/mnt/backup-drive/rsync-archive/"
DB_PATH="/mnt/backup-drive/backupdb.json"
EXCLUDE_FILE="/home/username/backup_logs/rsync-exclude.txt"
LOG_FILE="/home/username/backup_logs/rsync-backup.log"
MOUNT_POINT="/mnt/backup-drive"
DAYS_AFTER_DELETE=30

timestamp_now=$(date +%s)
timestamp_in_x_days=$(date -d "+$DAYS_AFTER_DELETE days" +%s)
DATED_ARCHIVE="$ARCHIVE_PATH$(date +%Y-%m-%d_%H-%M-%S)"

# Redirect output to log
exec 1>>"$LOG_FILE" 2>&1

echo "-----Starting backup run on $(date)-----"
echo ""

# Check if mount point is available
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "ERROR: External drive not mounted at $MOUNT_POINT"
    exit 1
fi

# Validate that required directories exist
for path_var in "$SOURCE_PATH" "$BACKUP_PATH" "$ARCHIVE_PATH"; do
    if [ ! -d "$path_var" ]; then
        echo "ERROR: Directory $path_var does not exist!"
        exit 1
    fi
done

# Check for dependencies
dependencies=("jq" "rsync")
for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" &> /dev/null; then
        echo "ERROR: $dependency not installed!"
        exit 1
    fi
done

# Build rsync options
RSYNC_OPTS="-rtlHs --delete --stats"
if [ -f "$EXCLUDE_FILE" ]; then
    RSYNC_OPTS="$RSYNC_OPTS --exclude-from=$EXCLUDE_FILE"
else
    echo "WARNING: Exclude file not found, using basic excludes"
    RSYNC_OPTS="$RSYNC_OPTS --exclude='.cache'"
fi

# Initialize database if it doesn't exist
if [ ! -f "$DB_PATH" ]; then
    echo '{"pending_deletion": []}' > "$DB_PATH"
    echo "Created new database at $DB_PATH"
fi

# Single rsync run with backup directory
mkdir -p "$DATED_ARCHIVE"
echo "Running rsync backup with archive..."

rsync $RSYNC_OPTS --backup --backup-dir="$DATED_ARCHIVE" "$SOURCE_PATH" "$BACKUP_PATH"

if [ $? -ne 0 ]; then
    echo "ERROR: rsync backup failed!"
    exit 1
fi

# Add archive to database if not empty
if [ -d "$DATED_ARCHIVE" ] && [ -n "$(ls -A "$DATED_ARCHIVE")" ]; then
    echo "Adding $DATED_ARCHIVE to pending deletion (expires in $DAYS_AFTER_DELETE days)..."
    jq '.pending_deletion += [{"path": "'"$DATED_ARCHIVE"'", "delete_on": '"$timestamp_in_x_days"'}]' "$DB_PATH" > "$DB_PATH.tmp" && mv "$DB_PATH.tmp" "$DB_PATH"
else
    echo "No files were archived"
    rmdir "$DATED_ARCHIVE" 2>/dev/null
fi

# Delete expired archives
echo ""
echo "Checking for expired archives..."
deletepaths=()
readarray -t deletepaths < <(jq -r '.pending_deletion[].path' "$DB_PATH")

for deletepath in "${deletepaths[@]}"; do
    timestamp=$(jq -r '[.pending_deletion[] | select(.path == "'"$deletepath"'").delete_on][0]' "$DB_PATH")
    if [[ $timestamp_now -ge $timestamp ]]; then
        if [[ -d "$deletepath" ]]; then
            echo "Deleting expired archive: $deletepath"
            rm -rf "$deletepath"
        fi
        jq 'del(.pending_deletion[] | select(.path == "'"$deletepath"'"))' "$DB_PATH" > "$DB_PATH.tmp" && mv "$DB_PATH.tmp" "$DB_PATH"
    fi
done

# Cleanup empty directories
find "$ARCHIVE_PATH" -type d -empty -delete 2>/dev/null

echo ""
echo "-----Run finished successfully at $(date)-----"
echo "===================================================================="
echo ""

exit 0
