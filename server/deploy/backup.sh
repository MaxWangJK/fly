#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
target=${1:?Usage: backup.sh /absolute/backup/directory}
mkdir -p "$target"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
# Stop writes for a consistent database + blob snapshot.
docker compose stop api
trap 'docker compose start api' EXIT
docker compose exec -T postgres pg_dump -U fly -Fc fly > "$target/fly-$stamp.dump"
docker compose run --rm --no-deps --user root --entrypoint tar api -C /var/lib/fly/storage -czf - . > "$target/fly-$stamp-blobs.tar.gz"
