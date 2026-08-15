-- Calculate hydrology hazard score for each road segment
ALTER TABLE analysis.road_hydro_features
    ADD COLUMN IF NOT EXISTS score_flowline DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS score_waterbody DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS score_elevation DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS score_slope DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS hydro_risk_score DOUBLE PRECISION;

UPDATE analysis.road_hydro_features
SET
    score_flowline = GREATEST(EXP(-LEAST(dist_flowline, 2000) / 100.0), 1e-6),
    score_waterbody = GREATEST(EXP(-LEAST(dist_waterbody, 2000) / 100.0), 1e-6);

WITH ranges AS (
    SELECT
        MIN(elevation) AS min_elevation,
        MAX(elevation) AS max_elevation,
        MIN(slope) AS min_slope,
        MAX(slope) AS max_slope
    FROM analysis.road_hydro_features
    WHERE elevation IS NOT NULL
      AND slope IS NOT NULL
)
UPDATE analysis.road_hydro_features f
SET
    score_elevation =
        1.0 - ((f.elevation - r.min_elevation) / NULLIF(r.max_elevation - r.min_elevation, 0)),
    score_slope =
        1.0 - ((f.slope - r.min_slope) / NULLIF(r.max_slope - r.min_slope, 0))
FROM ranges r
WHERE f.elevation IS NOT NULL
  AND f.slope IS NOT NULL;

UPDATE analysis.road_hydro_features
SET hydro_risk_score = 100.0 * (
      0.40 * score_flowline
    + 0.20 * score_waterbody
    + 0.20 * score_elevation
    + 0.20 * score_slope
);