#!/usr/bin/env bash
set -e

# DB connection parameters
DB=${DB:-postgis_road_flood_risk}

echo "=== Running PREP scripts ==="

# Create prep schema for cleaned and processed data
psql "$DB" -c "CREATE SCHEMA IF NOT EXISTS prep;"

# echo "Prep: States"
# psql "$DB" -f step03_prep/prep_states.sql

# echo "Prep: Roads"
# psql "$DB" -f step03_prep/prep_roads.sql

# echo "Prep: NHD Flowlines"
# psql "$DB" -f step03_prep/prep_nhd.sql

echo "Prep: DEM"
psql "$DB" -f step03_prep/prep_dem.sql

echo "=== PREP complete ==="
