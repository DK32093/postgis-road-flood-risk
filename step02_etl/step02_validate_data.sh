#!/usr/bin/env bash
set -e

mkdir -p logs
LOG="logs/validation_$(date +%Y-%m-%d_%H-%M-%S).log"

echo "=== Validation run: $(date) ===" >> $LOG
echo "" >> $LOG

echo "--- Validating State Boundaries ---" >> $LOG
ls -lh data/raw/NE_state_boundaries.shp >> $LOG
LAYER=$(ogrinfo data/raw/NE_state_boundaries.shp 2>/dev/null | grep "1:" | awk '{print $2}')

if [ -z "$LAYER" ]; then
    echo "[FAIL] ERROR: Could not read NE state boundaries shapefile. Missing files or corrupt shapefile." >> "$LOG"
else
    STATE_COUNT=$(ogrinfo -so data/raw/NE_state_boundaries.shp "$LAYER" | grep "Feature Count" | awk '{print $3}')
    EXTENT=$(ogrinfo -so data/raw/NE_state_boundaries.shp "$LAYER" | grep "Extent:" | sed 's/Extent: //')
    echo "Layer name: $LAYER" >> "$LOG"
    echo "Feature count: $STATE_COUNT" >> "$LOG"
    echo "Extent: $EXTENT" >> "$LOG"
fi
echo "" >> $LOG

echo "--- Validating OSM Northeast PBF ---" >> $LOG
ls -lh data/raw/osm_roads_northeast.osm.pbf >> $LOG
osmium fileinfo data/raw/osm_roads_northeast.osm.pbf >> $LOG
echo "" >> $LOG

echo "--- Validating NHD ---" >> $LOG
ls -lh data/raw/nhd_new_england.zip >> $LOG
echo "Total files in ZIP: $(zipinfo -1 data/raw/nhd_new_england.zip | wc -l)" >> "$LOG"
GDBTABLE_COUNT=$(zipinfo -1 data/raw/nhd_new_england.zip | grep -c ".gdbtable$")
echo "Number of .gdbtable files: $GDBTABLE_COUNT" >> "$LOG"

# Check for target layers in the GDB
GDB="/vsizip/data/raw/nhd_new_england.zip/NHDPLUS_H_0101_HU4_20220901_GDB.gdb"
for layer in NHDFlowline NHDWaterbody; do
    echo "Layer: $layer" >> "$LOG"

    # Check existence
    if ogrinfo "$GDB" "$layer" >/dev/null 2>&1; then
        echo "  [OK] Layer exists" >> "$LOG"

        # Extract geometry type
        GEOM_TYPE=$(ogrinfo -so "$GDB" "$layer" | grep "Geometry:" | awk '{print $2}')
        echo "  Geometry type: $GEOM_TYPE" >> "$LOG"

        # Extract feature count
        FEATURE_COUNT=$(ogrinfo -so "$GDB" "$layer" | grep "Feature Count" | awk '{print $3}')
        echo "  Feature count: $FEATURE_COUNT" >> "$LOG"
    else
        echo "  [FAIL] Layer missing" >> "$LOG"
    fi

    echo >> "$LOG"
done
echo "" >> $LOG

echo "--- Validating DEM tiles ---" >> "$LOG"

DEM_TILES=(data/raw/USGS30m_NE_tile_*.tif)

# Count tiles
COUNT=${#DEM_TILES[@]}
echo "Number of DEM tiles found: $COUNT" >> "$LOG"

# Warn if zero
if [ "$COUNT" -eq 0 ]; then
    echo "WARNING: No DEM tiles found. DEM fetch may have failed." >> "$LOG"
else
    # List sizes of each tile (lightweight)
    ls -lh data/raw/USGS30m_NE_tile_*.tif >> "$LOG"

    # Tiny structural check on the first tile
    FIRST_TILE="${DEM_TILES[0]}"
    echo "" >> $LOG
    echo " - Running gdalinfo on first tile: $FIRST_TILE" >> "$LOG"
    echo "" >> $LOG
    gdalinfo "$FIRST_TILE" >> "$LOG"
fi

echo "" >> "$LOG"