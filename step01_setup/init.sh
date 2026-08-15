#!/usr/bin/env bash
set -e

echo "----------------------------------------"
echo "creating postgis_road_flood_risk database"
echo "----------------------------------------"

# Connection parameters (local defaults)
PGUSER=$(whoami)
PGDATABASE=postgres

run_sql() {
  local script="$1"
  echo "▶ $script"
  psql -U "$PGUSER" -d "$PGDATABASE" -f "$script"
}

# Step 1: Create the database
run_sql setup/step01_create_database.sql
echo "Database created."

# Step 2: Connect to the new database and enable postgis extensions
PGDATABASE=postgis_road_flood_risk
run_sql setup/step02_extensions.sql
echo "Extensions enabled."
