-- Prep: NHD Flowlines clipped to NE
DROP TABLE IF EXISTS prep.nhd_flowlines_ne CASCADE;

CREATE TABLE prep.nhd_flowlines_ne AS
SELECT
    objectid,
    ftype,
    fcode,
    geom
FROM raw.flowlines
WHERE ST_Intersects(
        geom,
        (SELECT ST_Union(geom) FROM prep.states_ne)
    );

CREATE INDEX nhd_flowlines_ne_geom_idx
ON prep.nhd_flowlines_ne USING GIST(geom);

-- Prep: NHD Waterbodies clipped to NE
DROP TABLE IF EXISTS prep.nhd_waterbodies_ne CASCADE;

CREATE TABLE prep.nhd_waterbodies_ne AS
SELECT
    objectid,
    ftype,
    fcode,
    geom
FROM raw.waterbodies
WHERE ST_Intersects(
        geom,
        (SELECT ST_Union(geom) FROM prep.states_ne)
    );

CREATE INDEX nhd_waterbodies_ne_geom_idx
ON prep.nhd_waterbodies_ne USING GIST(geom);
