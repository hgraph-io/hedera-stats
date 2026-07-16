#!/usr/bin/env bash
#
# Deploy the ecosystem migrations into a network mirror-node database, where
# ecosystem.* is co-located with the replicated public.*/erc.* tables.
#
#   src/migrations/deploy.sh mainnet         # dry run — prints the plan
#   src/migrations/deploy.sh mainnet --run   # execute
#   src/migrations/deploy.sh testnet --run
#
# Connection identity is fixed per target: the Unix socket with peer auth as the
# postgres OS user (no password), and objects are owned by the per-network
# ecosystem_owner group role via PGOPTIONS (`-c role=...`) so every member of
# that role inherits access. The migration files are staged to a world-readable
# temp dir so the postgres OS user can read them when invoked via sudo.
#
# Prerequisites (provisioned externally by a superuser): the timestamp9 and http
# extensions, and the logical replication subscription that populates the mirror-
# node tables. These migrations are pure schema SQL and create neither.

set -euo pipefail
MIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-}"; shift || true
RUN=false
[ "${1:-}" = "--run" ] && RUN=true

case "$TARGET" in
  mainnet)
    PGPORT=5433
    PGDATABASE=hedera_mainnet
    OWNER_ROLE=hedera_mainnet_ecosystem_owner
    ;;
  testnet)
    PGPORT=5432
    PGDATABASE=hedera_testnet
    OWNER_ROLE=hedera_testnet_ecosystem_owner
    ;;
  *)
    echo "usage: $(basename "$0") <mainnet|testnet> [--run]" >&2
    exit 1 ;;
esac

PGHOST=/var/run/postgresql
PGUSER=postgres
STAGE_USER="${STAGE_USER:-postgres}"

cat <<PLAN
=== ecosystem deploy: ${TARGET} ===
  connect : ${PGDATABASE}@${PGHOST}:${PGPORT} as ${PGUSER} (run by OS user ${STAGE_USER})
  owner   : ${OWNER_ROLE} (set via PGOPTIONS role)
  step    : migrate.sh — apply unapplied migrations
PLAN

$RUN || { echo "(dry run — re-run with --run to execute)"; exit 0; }

# Stage the migrations to a world-readable dir so the postgres OS user can read
# them even when this repo checkout is not readable by that user.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/ecosystem-migrations.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -r "$MIG_DIR/." "$STAGE/"
chmod -R a+rX "$STAGE"

ENVS=(
  "PGHOST=$PGHOST"
  "PGPORT=$PGPORT"
  "PGDATABASE=$PGDATABASE"
  "PGUSER=$PGUSER"
  "PGOPTIONS=-c role=$OWNER_ROLE"
)

run_as_stage_user() {
  if [ "$(id -un)" = "$STAGE_USER" ]; then
    env "$@"
  else
    sudo -u "$STAGE_USER" env "$@"
  fi
}

echo "[deploy] applying migrations"
run_as_stage_user "${ENVS[@]}" bash "$STAGE/migrate.sh" "$STAGE"

echo "[deploy] done."
