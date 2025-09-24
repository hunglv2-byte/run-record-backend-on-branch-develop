#!/bin/bash

# ==============================
# Config
# ==============================
CONTAINER_NAME="${CONTAINER_NAME:-record-postgres15.12}"
DB_USER="justincase"
DB_NAME="record_db"
BACKUP_DIR="/home/dgwo/Documents/backup_data/${CONTAINER_NAME}"

mkdir -p "$BACKUP_DIR"

# ==============================
# Functions
# ==============================
backup_db() {
    TIMESTAMP=$(date +"%Y%m%d%H%M%S")
    BACKUP_FILE="${BACKUP_DIR}/${TIMESTAMP}_backup.sql.gz"
    echo ">>> Starting backup: $BACKUP_FILE"
    docker exec -t "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"
    echo ">>> Backup completed: $BACKUP_FILE"
}

restore_db() {
    if [ -z "$1" ]; then
        echo "Usage: $0 restore <backup_file.sql.gz>"
        exit 1
    fi

    BACKUP_FILE="$1"

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    echo ">>> Restoring from $BACKUP_FILE ..."
    gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME"
    echo ">>> Restore completed"
}

# ==============================
# Main
# ==============================
case "$1" in
    backup)
        backup_db
        ;;
    restore)
        restore_db "$2"
        ;;
    *)
        echo "Usage: $0 {backup|restore <file.sql.gz>}"
        exit 1
        ;;
esac
