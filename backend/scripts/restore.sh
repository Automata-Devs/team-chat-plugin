#!/usr/bin/env sh
# Restores a backup into an EMPTY database (it refuses a database with tables).
# Stop the API first, restore, then start it: migrations newer than the
# backup run on start.
#
#   DATABASE_URL=postgres://.../teamchat_restored ./scripts/restore.sh backups/teamchat-20261112T030000Z.dump
set -eu

: "${DATABASE_URL:?set DATABASE_URL}"
FILE="${1:?usage: restore.sh <backup.dump>}"
[ -f "$FILE" ] || { echo "No such file: $FILE" >&2; exit 1; }

TABLES=$(psql "$DATABASE_URL" -Atc "select count(*) from information_schema.tables where table_schema in ('public', 'drizzle')")
if [ "$TABLES" != "0" ]; then
	echo "The target database isn't empty ($TABLES tables). Restore into a new database, then switch DATABASE_URL." >&2
	exit 1
fi

pg_restore --no-owner --no-privileges --exit-on-error --dbname="$DATABASE_URL" "$FILE"
psql "$DATABASE_URL" -Atc "select 'messages: ' || count(*) from messages; select 'users: ' || count(*) from users"
echo "Restored $FILE"
