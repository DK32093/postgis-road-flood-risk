#!/usr/bin/env bash
set -e

# DB connection parameters
DB=${DB:-postgis_road_flood_risk}

echo "=== Running ANALYSIS scripts ==="

# Create analysis schema for cleaned and processed data
psql "$DB" -c "CREATE SCHEMA IF NOT EXISTS analysis;"

# echo "Analysis: Road Segments"
# psql "$DB" -f step04_analysis/step01_segment_roads.sql

# echo "Analysis: Terrain Assignment"
# psql "$DB" -f step04_analysis/step02_assign_terrain.sql

# echo "Analysis: Distance to Hydro Features"
# psql "$DB" -f step04_analysis/step03_assign_distances.sql

# echo "Analysis: Calculate Hydro Risk Scores"
# psql "$DB" -f step04_analysis/step04_calculate_score.sql

echo "Analysis: Create Hex Grid Summary"
psql "$DB" -f step04_analysis/step05_create_hex_summary.sql

echo "=== ANALYSIS complete ==="