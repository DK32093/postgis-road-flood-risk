-- 1. Create hex grid
drop table if exists analysis.hex_ne cascade;
CREATE TABLE analysis.hex_ne AS
SELECT *
FROM ST_HexagonGrid(
    2000,  -- hex size in meters
    (SELECT ST_Extent(midpoint_geom)::geometry FROM analysis.road_hydro_features)
) AS hex;

ALTER TABLE analysis.hex_ne
    ALTER COLUMN geom TYPE geometry(Polygon, 5070)
    USING ST_SetSRID(geom, 5070);

-- 2. Add a unique ID column
ALTER TABLE analysis.hex_ne ADD COLUMN id SERIAL;

-- 3. Add risk score and stats column
ALTER TABLE analysis.hex_ne 
    ADD COLUMN avg_hydro_risk DOUBLE PRECISION,
    ADD COLUMN avg_dist_flowline DOUBLE PRECISION,
    ADD COLUMN avg_dist_waterbody DOUBLE PRECISION,
    ADD COLUMN avg_elevation DOUBLE PRECISION,
    ADD COLUMN avg_slope DOUBLE PRECISION;

-- 4. Add spatial index
CREATE INDEX idx_hex_geom ON analysis.hex_ne USING GIST (geom);

-- 5. clip hexes to NE state boundaries
DELETE FROM analysis.hex_ne h
WHERE NOT EXISTS (
    SELECT 1
    FROM prep.states_ne b
    WHERE ST_Intersects(h.geom, b.geom)
);

-- 6. Aggregate mean hydrology risk per hex
UPDATE analysis.hex_ne h
SET 
    avg_hydro_risk = ROUND(sub.avg_score),
    avg_dist_flowline = ROUND(sub.avg_dist_flowline),
    avg_dist_waterbody = ROUND(sub.avg_dist_waterbody),
    avg_elevation = ROUND(sub.avg_elevation),
    avg_slope = ROUND(sub.avg_slope)
FROM (
    SELECT
        hex.id,
        AVG(r.hydro_risk_score) AS avg_score,
        AVG(r.dist_flowline) AS avg_dist_flowline,
        AVG(r.dist_waterbody) AS avg_dist_waterbody,
        AVG(r.elevation) AS avg_elevation,
        AVG(r.slope) AS avg_slope
    FROM analysis.hex_ne hex
    JOIN analysis.road_hydro_features r
      ON r.midpoint_geom && hex.geom
     AND ST_Intersects(r.midpoint_geom, hex.geom)
    GROUP BY hex.id
) sub
WHERE h.id = sub.id;

-- 7. Fill in missing hexes with average of neighbors
UPDATE analysis.hex_ne h
SET avg_hydro_risk = nn.avg_neighbor
FROM (
    SELECT h1.id,
           AVG(h2.avg_hydro_risk) AS avg_neighbor
    FROM analysis.hex_ne h1
    JOIN analysis.hex_ne h2
      ON ST_DWithin(h1.geom, h2.geom, 2500)  -- ~1 hex radius
     AND h2.avg_hydro_risk IS NOT NULL
    WHERE h1.avg_hydro_risk IS NULL
    GROUP BY h1.id
) nn
WHERE h.id = nn.id;

-- 8. Cap the average hydrology risk at the 99th percentile for visualization purposes
WITH stats AS (
    SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY avg_hydro_risk) AS p99
    FROM analysis.hex_ne
)
UPDATE analysis.hex_ne h
SET avg_hydro_risk = LEAST(h.avg_hydro_risk, stats.p99)
FROM stats;

