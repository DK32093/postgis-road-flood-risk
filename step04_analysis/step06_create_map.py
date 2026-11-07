import geopandas as gpd
import folium
from folium import FeatureGroup
from folium.features import GeoJson, GeoJsonTooltip
from sqlalchemy import create_engine

engine = create_engine("postgresql://dylan@localhost/postgis_road_flood_risk")

hexes = gpd.read_postgis(
    "SELECT geom, id, avg_hydro_risk, avg_dist_flowline, avg_dist_waterbody, avg_elevation, avg_slope FROM analysis.hex_ne",
    engine,
    geom_col="geom"
)

m = folium.Map(location=[44.2, -70], zoom_start=7)

# --- Add NE state boundaries as a separate toggleable layer ---
state_ne = gpd.read_postgis(
    "SELECT geom, name FROM prep.states_ne",
    engine,
    geom_col="geom"
)

state_layer = folium.FeatureGroup(name="NE State Boundaries", show=True)

GeoJson(
    state_ne,
    style_function=lambda f: {
        "color": "black",
        "weight": 1,
        "fillOpacity": 0
    }
).add_to(state_layer)

state_layer.add_to(m)

choropleth = folium.Choropleth(
    geo_data=hexes,
    data=hexes,
    columns=[
            "id",
            "avg_hydro_risk",
            "avg_dist_flowline",
            "avg_dist_waterbody",
            "avg_elevation",
            "avg_slope"
            ],
    key_on="feature.properties.id",
    fill_color="Blues",
    fill_opacity=0.9,
    line_opacity=0.0,
    legend_name="Average Road Hydrology Risk Score",
).add_to(m)

# Hover tooltips
GeoJsonTooltip(
        fields=[
            "id",
            "avg_hydro_risk",
            "avg_dist_flowline",
            "avg_dist_waterbody",
            "avg_elevation",
            "avg_slope"
        ],
        aliases=[
            "Hex ID:",
            "Avg Hydro Risk:",
            "Avg Dist to Flowline (m):",
            "Avg Dist to Waterbody (m):",
            "Avg Elevation (m):",
            "Avg Slope (%):"
        ],
        localize=True,
        sticky=False,
        labels=True,
    ).add_to(choropleth.geojson)

folium.LayerControl().add_to(m)

m.save("docs/hex_2km_avg_road_hydro_risk_map.html")
