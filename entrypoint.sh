#!/bin/sh
set -e

SQL_DIR=/opt/datomic/bin/sql

wait_for_postgres() {
  tries=0
  until psql -qtAc 'SELECT 1' >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 60 ]; then
      echo "Postgres at $PGHOST:$PGPORT not reachable as $PGUSER" >&2
      exit 1
    fi
    echo "Waiting for Postgres ($tries/60)..."
    sleep 2
  done
}

export PGHOST="${DATOMIC_DB_HOST:?DATOMIC_DB_HOST is required}"
export PGPORT="${DATOMIC_DB_PORT:-5432}"
DB_NAME="${DATOMIC_DB_NAME:-datomic}"

# One-shot mode: run Datomic's bin/sql scripts (unmodified) with admin credentials.
# Each script is skipped if what it creates already exists, so this is safe to re-run.
if [ "${1:-}" = "init-db" ]; then
  # the scripts hardcode the database and role name
  [ "$DB_NAME" = "datomic" ] || { echo "init-db requires DATOMIC_DB_NAME=datomic" >&2; exit 1; }
  export PGUSER="${DATOMIC_ADMIN_USER:-postgres}"
  export PGPASSWORD="${DATOMIC_ADMIN_PASSWORD:?DATOMIC_ADMIN_PASSWORD is required for init-db}"
  export PGDATABASE=postgres
  wait_for_postgres

  if [ -z "$(psql -qtAc "SELECT 1 FROM pg_database WHERE datname='datomic'")" ]; then
    echo "Creating database (postgres-db.sql)"
    psql -v ON_ERROR_STOP=1 -q -f "$SQL_DIR/postgres-db.sql"
  fi

  export PGDATABASE=datomic
  if [ -z "$(psql -qtAc "SELECT to_regclass('public.datomic_kvs')")" ]; then
    echo "Creating table (postgres-table.sql)"
    psql -v ON_ERROR_STOP=1 -q -f "$SQL_DIR/postgres-table.sql"
  fi

  if [ -z "$(psql -qtAc "SELECT 1 FROM pg_roles WHERE rolname='datomic'")" ]; then
    echo "Creating role (postgres-user.sql)"
    psql -v ON_ERROR_STOP=1 -q -f "$SQL_DIR/postgres-user.sql"
    # the script hardcodes the password 'datomic'; replace it
    if [ -n "${DATOMIC_DB_PASSWORD:-}" ]; then
      echo "ALTER ROLE datomic PASSWORD :'pw'" | psql -v ON_ERROR_STOP=1 -q -v pw="$DATOMIC_DB_PASSWORD"
    fi
  fi
  echo "init-db complete"
  exit 0
fi

# Normal mode: start the transactor
: "${DATOMIC_DB_USER:?DATOMIC_DB_USER is required}"
: "${DATOMIC_DB_PASSWORD:?DATOMIC_DB_PASSWORD is required}"
export DATOMIC_DB_PORT="$PGPORT" DATOMIC_DB_NAME="$DB_NAME"
export DATOMIC_PORT="${DATOMIC_PORT:-4334}"
export DATOMIC_ALT_HOST="${DATOMIC_ALT_HOST:-$(hostname)}"
export PGDATABASE="$DB_NAME" PGUSER="$DATOMIC_DB_USER" PGPASSWORD="$DATOMIC_DB_PASSWORD"

wait_for_postgres
if [ -z "$(psql -qtAc "SELECT to_regclass('public.datomic_kvs')")" ]; then
  echo "Table datomic_kvs not found in $DB_NAME. Run this image once with the 'init-db' argument." >&2
  exit 1
fi

envsubst < /opt/datomic/transactor.properties.template > /tmp/transactor.properties

# Optional: only needed if your Datomic version/licensing requires a key
if [ -n "${DATOMIC_LICENSE_KEY:-}" ]; then
  echo "license-key=${DATOMIC_LICENSE_KEY}" >> /tmp/transactor.properties
fi

exec /opt/datomic/bin/transactor /tmp/transactor.properties
