#!/bin/bash

# Quickstart: modify the variables in all caps.
# For the first 3 make sure the folders exist and there is a slash at the end.

SOURCE_PATH="/home/username/"              # Directory to backup
BACKUP_PATH="/mnt/backup-drive/backup/"    # Backup destination
ARCHIVE_PATH="/mnt/backup-drive/rsync-archive/"  # Archive location
DB_PATH="/mnt/backup-drive/backupdb.json"  # Database file
EXCLUDE_FILE="/path/to/rsync-exclude.txt"  # Optional: exclude patterns
LOG_FILE="/path/to/backup.log"             # Log file location
MOUNT_POINT="/mnt/backup-drive"            # Mount point to check
DAYS_AFTER_DELETE=30                       # Archive retention in days

timestamp_now=$(date +%s)
timestamp_in_x_days=$(date -d "+$DAYS_AFTER_DELETE days" +%s)

# This is used for logging. No idea how it works, but it works :)
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>"$LOG_FILE" 2>&1

echo "-----Starting run on $(date)-----"
echo ""

# Check if backup location is mounted
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "ERROR: Backup location $MOUNT_POINT is not mounted!"
    echo ""
    echo "-----Run finished at $(date)-----"
    echo ""
    echo "===================================================================="
    echo ""
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

        echo ""
        echo "-----Run finished at $(date)-----"
        echo ""
        echo "===================================================================="
        echo ""

        exit 1
    fi
done

# Build rsync command with exclude file if it exists
# You can modify the base flags to your liking
# (make sure you keep -a and -R otherwise it might break stuff. -v is recommended for logging)
RSYNC_BASE_FLAGS="-aRv"

# Optional: Use -rtlHs instead of -a for better NTFS compatibility
# Uncomment the line below if backing up to NTFS drives
# RSYNC_BASE_FLAGS="-rtlHsRv"

if [ -f "$EXCLUDE_FILE" ]; then
    RSYNC_OPTS="$RSYNC_BASE_FLAGS --exclude-from=$EXCLUDE_FILE"
    echo "Using exclude file: $EXCLUDE_FILE"
else
    # Fallback to basic excludes if file doesn't exist
    RSYNC_OPTS="$RSYNC_BASE_FLAGS --exclude='.cache'"
    echo "No exclude file found, using default excludes"
fi

# Do the backup normally, let rsync handle everything
echo "Running rsync backup..."
rsync $RSYNC_OPTS "$SOURCE_PATH" "$BACKUP_PATH"

if [ $? -ne 0 ]; then
    echo "ERROR: rsync backup failed!"
    echo ""
    echo "-----Run finished at $(date)-----"
    echo ""
    echo "===================================================================="
    echo ""
    exit 1
fi

# If the db doesn't exist, make a template json and exit
if [ ! -f "$DB_PATH" ]; then
    echo '{"pending_deletion": []}' > "$DB_PATH"

    echo ""
    echo "-----Run finished at $(date)-----"
    echo ""
    echo "===================================================================="
    echo ""

    exit 0
fi

# Read db and determine which files/folders should be deleted according to their delete time
# then delete them and remove the db entry
deletepaths=()
readarray -t deletepaths < <(jq -r '.pending_deletion[].path' "$DB_PATH")

for deletepath in "${deletepaths[@]}"; do
    timestamp=$(jq -r '[.pending_deletion[] | select(.path == "'"$deletepath"'").delete_on][0]' "$DB_PATH")
    if [[ $timestamp_now -ge $timestamp ]]; then
        if [[ -f "$deletepath" || -d "$deletepath" ]]; then
            echo "Deleting $deletepath from the archive..."
            rm -rf "$deletepath"
        fi
        if ! jq 'del(.pending_deletion[] | select(.path == "'"$deletepath"'"))' "$DB_PATH" > "$DB_PATH.tmp"; then
            echo "ERROR: Failed to update database"
            rm -f "$DB_PATH.tmp"
            exit 1
        fi
        mv "$DB_PATH.tmp" "$DB_PATH"
    fi
done

# Get list of files/folders that rsync thinks should be deleted
# then move them to the archive and mark them for deletion on today + x days
#
# We sort the path list alphabetically so if a whole folder was deleted, it first processes the parent folder and then the
# other files (which get skipped because they have been moved to the archive and don't exist anymore).
# This saves time and db entries :)

echo ""
echo "Preparing move to archive..."

paths=()
readarray -t paths < <(rsync $RSYNC_OPTS --delete -n "$SOURCE_PATH" "$BACKUP_PATH" | grep deleting | sed "s|deleting ||g" | sort)

for path in "${paths[@]}"; do
    if [[ -f "$BACKUP_PATH$path" || -d "$BACKUP_PATH$path" ]]; then
        if [[ -d "$BACKUP_PATH$path" ]]; then # folder
            mkdir -p "$ARCHIVE_PATH$path"
            echo "Moving folder $BACKUP_PATH$path to archive ($ARCHIVE_PATH$path)..."
            cp -a "$BACKUP_PATH$path/." "$ARCHIVE_PATH$path/"
            if [ $? -ne 0 ]; then
                echo "WARNING: Failed to copy folder $BACKUP_PATH$path to archive"
                continue
            fi
        else # file
            mkdir -p "$(dirname "$ARCHIVE_PATH$path")"
            echo "Moving file $BACKUP_PATH$path to archive ($(dirname "$ARCHIVE_PATH$path"))..."
            cp -a "$BACKUP_PATH$path" "$(dirname "$ARCHIVE_PATH$path")/"
            if [ $? -ne 0 ]; then
                echo "WARNING: Failed to copy file $BACKUP_PATH$path to archive"
                continue
            fi
        fi
        rm -rf "$BACKUP_PATH$path"
        if ! jq '.pending_deletion += [{"path": "'"$ARCHIVE_PATH$path"'", "delete_on": '"$timestamp_in_x_days"'}]' "$DB_PATH" > "$DB_PATH.tmp"; then
            echo "ERROR: Failed to update database"
            rm -f "$DB_PATH.tmp"
            exit 1
        fi
        mv "$DB_PATH.tmp" "$DB_PATH"
    fi
done

# Delete empty folders from the archive
# Sometimes folders are left over from deleted files. Who needs empty folders?
if [[ -d "$ARCHIVE_PATH" ]]; then
    find "$ARCHIVE_PATH" -type d -empty -delete
fi

echo ""
echo "-----Run finished at $(date)-----"
echo ""
echo "===================================================================="
echo ""

exit 0
