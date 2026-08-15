DROP TABLE IF EXISTS prep.roads_ne CASCADE;

CREATE TABLE prep.roads_ne AS
SELECT
    osm_id,
    highway,
    way AS geom
FROM raw.osm_line
WHERE highway IS NOT NULL
AND ST_Intersects(
        way,
        (SELECT ST_Union(geom) FROM prep.states_ne)
    );

CREATE INDEX roads_ne_geom_idx
ON prep.roads_ne USING GIST(geom);
