# rsync-deleted-files-archive
Bash script for backup based on rsync with deleted file archive and auto-delete functionality

## 2025 Fork Improvements

This fork adds practical enhancements to the original script while preserving its excellent core design:

### Enhancements
- **Mount point verification**: Prevents backup attempts when drives aren't mounted
- **Exclude file support**: Use external rsync exclude files instead of hardcoded patterns
- **Configurable logging**: Log file path now easily configurable via variable
- **Better error messages**: More descriptive output for troubleshooting
- **Optional NTFS compatibility**: Commented flag option for cross-platform backups

### What Stayed the Same
The original two-pass rsync approach is maintained - it's clear, effective, and ensures the backup destination remains a perfect 1:1 mirror of the source. The manual archiving process gives you full control over what gets archived (deleted files only, not modified versions).

---

## Original Project Info

Note: This script hasn't been tested extensively and it's **not** that good at making sure nothing gets accidentally deleted. So use this at your own risk. If you find any bug, feel free to [open an issue](https://github.com/1nikolas/rsync-deleted-files-archive/issues).

## Quickstart
First of all make sure you have `jq` and `rsync` installed. Everything else should be pre-installed on any modern linux system. Then download the script and read the comments in order to modify it to your likings. To automate this you can use [systemd timers](https://wiki.archlinux.org/title/Systemd/Timers).

## What?
This script is an rsync wrapper with support for deleted file archive and auto-delete. It basically makes a backup from a (your PC) to b (your backup) and then checks if files deleted from a are still on b. Said files will be moved into a pre-determined archive directory and be auto-deleted after a certain amount of days after they were deleted (which you can configure).

## Why?
Back when I had Windows, I used to have [bvckup2](https://bvckup2.com/) for my backups. This had an option to archive deleted files on a specific directory and then auto-delete them after a certain amount of days. I searched really deep for something like this but the closest thing I got was snapshot rsync apps (like rsnapshot) which create a mess on the backup (I don't want multiple versions of a file, one is fine for me). So I just made this; a simple script which does exactly that, based on rsync.

## How?
This script works by first making a normal copy with rsync and then doing a dry run of `rsync --delete`. It parses all the files rsync thinks need to be deleted, moves them into an archive folder, and saves them in a JSON database for deletion after a specified number of days. This two-pass approach keeps the backup as a clean 1:1 mirror while safely archiving deletions.

## Configuration

Edit these variables at the top of the script:

```
SOURCE_PATH="/home/username/"              # Directory to backup
BACKUP_PATH="/mnt/backup-drive/backup/"    # Backup destination
ARCHIVE_PATH="/mnt/backup-drive/rsync-archive/"  # Archive location
DB_PATH="/mnt/backup-drive/backupdb.json"  # Database file
EXCLUDE_FILE="/path/to/rsync-exclude.txt"  # Optional: exclude patterns
LOG_FILE="/path/to/backup.log"             # Log file location
MOUNT_POINT="/mnt/backup-drive"            # Mount point to check
DAYS_AFTER_DELETE=30                       # Archive retention in days
```

### Optional: NTFS Compatibility

If backing up to an NTFS drive (common for external drives), uncomment this line in the script:

```
# RSYNC_BASE_FLAGS="-rtlHsRv"  # Uncomment for NTFS drives
```

This uses specific flags that work better with NTFS than the default `-a` (archive) flag.

## Exclude File Example

Create a file at the path specified in `EXCLUDE_FILE`:

```
.cache
.local/share/Trash
.thumbnails
node_modules
__pycache__
*.tmp
```

## Systemd Automation Example

Create `/etc/systemd/system/backup-archive.service`:
```
[Unit]
Description=Rsync Backup with Archive

[Service]
Type=oneshot
User=yourusername
ExecStart=/path/to/backup-archive.sh
```

Create `/etc/systemd/system/backup-archive.timer`:
```
[Unit]
Description=Daily Backup Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:
```
sudo systemctl daemon-reload
sudo systemctl enable backup-archive.timer
sudo systemctl start backup-archive.timer
```

## Archive Structure

After running, your archives will look like this:

```
/mnt/backup-drive/rsync-archive/
├── Documents/
│   └── deleted-file.txt
├── Pictures/
│   └── old-photo.jpg
└── .config/
    └── old-settings.conf
```

Files are preserved in their original directory structure for easy recovery.

## Database Format

The script tracks archives in a JSON database:

```
{
  "pending_deletion": [
    {
      "path": "/mnt/backup-drive/rsync-archive/Documents/deleted-file.txt",
      "delete_on": 1734595200
    }
  ]
}
```

## License
```
MIT License
Copyright (c) 2022 Nikolas Spiridakis
Copyright (c) 2025 Community Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```