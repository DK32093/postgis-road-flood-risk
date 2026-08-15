#!/usr/bin/env bash
set -e

# DB connection parameters
DB=${DB:-postgis_road_flood_risk}
USER=${USER:-dylan}
PG_CONN="dbname=$DB user=$USER"

# Create raw schema for ingestion
psql "$DB" -c "CREATE SCHEMA IF NOT EXISTS raw;"

# Ingest datasets
echo "=== Ingesting OSM ==="
PBF="data/raw/osm_roads_northeast.osm.pbf"

# GIST indexes are created automatically by osm2pgsql
osm2pgsql \
  --create \
  --database "$DB" \
  --schema raw \
  --prefix osm \
  --slim \
  --hstore \
  --proj=5070 \
  data/raw/osm_roads_northeast.osm.pbf

echo "OSM ingestion complete."

echo "=== Ingesting NHD ==="

# Extract FGDB
unzip -q data/raw/nhd_new_england.zip -d data/nhd
GDB="data/nhd/NHDPLUS_H_0101_HU4_20220901_GDB.gdb"

# Ingest Flowlines
ogr2ogr -f PostgreSQL PG:"$PG_CONN" \
    "$GDB" NHDFlowline -nln raw.flowlines \
    -t_srs EPSG:5070 \
    -lco GEOMETRY_NAME=geom

# Ingest Waterbodies
ogr2ogr -f PostgreSQL PG:"$PG_CONN" \
    "$GDB" NHDWaterbody -nln raw.waterbodies \
    -t_srs EPSG:5070 \
    -lco GEOMETRY_NAME=geom

# Indexes
psql "$DB" -c "CREATE INDEX IF NOT EXISTS flowlines_geom_idx ON raw.flowlines USING GIST(geom);"
psql "$DB" -c "CREATE INDEX IF NOT EXISTS waterbodies_geom_idx ON raw.waterbodies USING GIST(geom);"

echo "NHD ingestion complete"

echo "=== Ingesting USGS 3DEP ==="
mkdir -p data/raw/dem_5070
for TILE in data/raw/*.tif; do # Reproject DEM tiles to EPSG:5070
    NAME=$(basename "$TILE")
    gdalwarp \
        -t_srs EPSG:5070 \
        -r bilinear \
        -tr 30 30 \
        -tap \
        "$TILE" \
        "data/raw/dem_5070/$NAME"
done

FIRST=1 # Use the first tile to create the table, then append the rest

for TILE in data/raw/dem_5070/*.tif; do
    if [ $FIRST -eq 1 ]; then
        raster2pgsql -s 5070 -I -M -t 512x512 "$TILE" raw.dem_tiles | psql "$DB"
        FIRST=0
    else
        raster2pgsql -a -s 5070 -t 512x512 "$TILE" raw.dem_tiles | psql "$DB"
    fi
done

echo "USGS 3DEP ingestion complete."

echo "=== Ingesting NE State Boundaries ==="

# Shapefile path
STATES_SHP="data/raw/NE_state_boundaries.shp"

# Reproject to EPSG:5070
ogr2ogr -t_srs EPSG:5070 data/raw/NE_state_boundaries_5070.shp "$STATES_SHP"

# Ingest into raw.states_ne
shp2pgsql -I -s 5070 "data/raw/NE_state_boundaries_5070.shp" raw.states_ne | psql "$DB"

echo "NE State Boundaries ingestion complete."
