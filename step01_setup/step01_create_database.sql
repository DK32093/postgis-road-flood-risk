-- Create database
SELECT 'CREATE DATABASE postgis_road_flood_risk'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'postgis_road_flood_risk'
) \gexec
