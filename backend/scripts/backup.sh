#!/usr/bin/env sh
# Backs up the database to backups/teamchat-<UTC time>.dump (pg_dump custom
# format: compressed, restorable table by table) and keeps the newest $KEEP.
#
#   DATABASE_URL=postgres://... ./scripts/backup.sh
#   docker compose exec postgres sh -c 'BACKUP_DIR=/backups DATABASE_URL=postgres://teamchat:$POSTGRES_PASSWORD@localhost/teamchat /scripts/backup.sh'
#
# Run it from cron. For point-in-time recovery also use WAL archiving or a
# managed database's backups; see docs/backend/OPERATIONS.md.
set -eu

: "${DATABASE_URL:?set DATABASE_URL}"
DIR="${BACKUP_DIR:-$(dirname "$0")/../backups}"
KEEP="${KEEP:-14}"
mkdir -p "$DIR"

FILE="$DIR/teamchat-$(date -u +%Y%m%dT%H%M%SZ).dump"
pg_dump --format=custom --no-owner --no-privileges --file="$FILE.partial" "$DATABASE_URL"
# A dump pg_restore can't read is not a backup
pg_restore --list "$FILE.partial" > /dev/null
mv "$FILE.partial" "$FILE"
echo "Backed up to $FILE ($(du -h "$FILE" | cut -f1))"

ls -1t "$DIR"/teamchat-*.dump 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do rm -f "$old"; done
