-- Prep: NE State Boundaries
DROP TABLE IF EXISTS prep.states_ne CASCADE;

CREATE TABLE prep.states_ne AS
SELECT *
FROM raw.states_ne;

-- Index
CREATE INDEX states_ne_geom_idx
ON prep.states_ne USING GIST(geom);
