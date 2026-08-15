-- Break up roads into segments and compute midpoints
DROP TABLE IF EXISTS analysis.road_segments CASCADE;

CREATE TABLE analysis.road_segments AS
WITH exploded AS (
    SELECT
        osm_id,
        highway,
        (ST_Dump(geom)).geom AS geom
    FROM prep.roads_ne
),
segmented AS (
    SELECT
        osm_id,
        highway,
        ST_Segmentize(geom, 40) AS geom  -- segment length max = 40 meters
    FROM exploded
),
final AS (
    SELECT
        osm_id,
        highway,
        (ST_DumpSegments(geom)).geom AS geom
    FROM segmented
)
SELECT
    row_number() OVER () AS segment_id,
    osm_id,
    highway,
    geom AS segment_geom,
    ST_LineInterpolatePoint(geom, 0.5) AS midpoint_geom
FROM final;

-- Indexes
CREATE INDEX road_segments_segment_geom_idx
    ON analysis.road_segments USING GIST(segment_geom);

CREATE INDEX road_segments_midpoint_geom_idx
    ON analysis.road_segments USING GIST(midpoint_geom);
