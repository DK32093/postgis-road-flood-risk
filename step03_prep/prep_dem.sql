-- Prep: DEM clipped to NE states
DROP TABLE IF EXISTS prep.dem_ne CASCADE;

CREATE TABLE prep.dem_ne AS
SELECT
    rid,
    ST_Clip(rast, (SELECT ST_Union(geom) FROM prep.states_ne)) AS rast
FROM raw.dem_tiles
WHERE ST_Intersects(
        ST_ConvexHull(rast),
        (SELECT ST_Union(geom) FROM prep.states_ne)
    );

CREATE INDEX dem_ne_rast_idx
ON prep.dem_ne USING GIST (ST_ConvexHull(rast));

-- Prep: Slope surface from clipped DEM
DROP TABLE IF EXISTS prep.dem_slope_ne CASCADE;

CREATE TABLE prep.dem_slope_ne AS
SELECT
    rid,
    ST_Tile(
        ST_Slope(rast, 1, '32BF', 'DEGREES'),
        512, 512
    ) AS rast
FROM prep.dem_ne;

CREATE INDEX dem_slope_ne_rast_idx
ON prep.dem_slope_ne USING GIST (ST_ConvexHull(rast));
