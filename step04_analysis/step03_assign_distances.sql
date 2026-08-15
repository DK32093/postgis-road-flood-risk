-- Calculate distance from each road segment to the nearest flowline.
ALTER TABLE analysis.road_hydro_features
    ADD COLUMN IF NOT EXISTS dist_flowline DOUBLE PRECISION;

UPDATE analysis.road_hydro_features AS f
SET dist_flowline = (
    SELECT ST_Distance(f.midpoint_geom, fl.geom)
    FROM prep.nhd_flowlines_ne AS fl
    ORDER BY f.midpoint_geom <-> fl.geom
    LIMIT 1
);

ALTER TABLE analysis.road_hydro_features
    ADD COLUMN IF NOT EXISTS dist_waterbody DOUBLE PRECISION;

UPDATE analysis.road_hydro_features AS f
SET dist_waterbody = (
    SELECT ST_Distance(f.midpoint_geom, wb.geom)
    FROM prep.nhd_waterbodies_ne AS wb
    ORDER BY f.midpoint_geom <-> wb.geom
    LIMIT 1
);


