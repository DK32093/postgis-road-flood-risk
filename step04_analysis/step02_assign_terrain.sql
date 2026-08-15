-- Assign slope and elevation to road segments using DEM and slope raster tables.
SET max_parallel_workers_per_gather = 8;
SET client_min_messages = ERROR;

CREATE TABLE analysis.road_dem AS
SELECT
    rs.segment_id,
    ST_Value(d.rast, 1, rs.midpoint_geom) AS elevation
FROM analysis.road_segments rs
CROSS JOIN LATERAL (
    SELECT d.rast
    FROM prep.dem_ne d
    WHERE rs.midpoint_geom && ST_ConvexHull(d.rast)
      AND ST_Intersects(rs.midpoint_geom, ST_ConvexHull(d.rast))
    LIMIT 1
) d;

CREATE TABLE analysis.road_slope AS
SELECT
    rs.segment_id,
    ST_Value(s.rast, 1, rs.midpoint_geom) AS slope
FROM analysis.road_segments rs
CROSS JOIN LATERAL (
    SELECT s.rast
    FROM prep.dem_slope_ne s
    WHERE rs.midpoint_geom && ST_ConvexHull(s.rast)
      AND ST_Intersects(rs.midpoint_geom, ST_ConvexHull(s.rast))
    LIMIT 1
) s;

-- Join the road segments with their corresponding elevation and slope values
CREATE TABLE analysis.road_hydro_features AS
SELECT
    rs.segment_id,
    rs.osm_id,
    rs.highway,
    rs.midpoint_geom, 
    dem.elevation,
    slope.slope
FROM analysis.road_segments rs
JOIN analysis.road_dem dem USING (segment_id)
JOIN analysis.road_slope slope USING (segment_id);

ALTER TABLE analysis.road_hydro_features
    ADD PRIMARY KEY (segment_id);

CREATE INDEX road_hydro_features_midpoint_geom_idx
ON analysis.road_hydro_features
USING GIST (midpoint_geom);

RESET client_min_messages;