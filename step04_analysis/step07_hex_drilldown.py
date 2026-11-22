import geopandas as gpd
import folium
from folium.features import GeoJsonTooltip
from sqlalchemy import create_engine, text
import tempfile
import rasterio
import numpy as np
from matplotlib import cm
from matplotlib import colors
from folium.raster_layers import ImageOverlay
from pyproj import Transformer
from rasterio.transform import from_origin
from rasterio.warp import reproject
from rasterio.warp import calculate_default_transform
from rasterio.enums import Resampling

# ============================================================
# CONFIG
# ============================================================

HEX_ID = 27356

OUTPUT_HTML = f"docs/hex_{HEX_ID}_drilldown.html"

engine = create_engine(
    "postgresql://dylan@localhost/postgis_road_flood_risk"
)

def road_color(score):

    if score <= q20:
        return "#fee5d9"

    elif score <= q40:
        return "#fcbba1"

    elif score <= q60:
        return "#fc9272"

    elif score <= q80:
        return "#ef3b2c"

    else:
        return "#99000d"

# ============================================================
# TARGET HEX
# ============================================================

target_hex = gpd.read_postgis(
    f"""
    SELECT
        id,
        avg_hydro_risk,
        avg_dist_flowline,
        avg_dist_waterbody,
        avg_elevation,
        avg_slope,
        geom
    FROM analysis.hex_ne
    WHERE id = {HEX_ID}
    """,
    engine,
    geom_col="geom"
)

if target_hex.empty:
    raise ValueError(f"Hex ID {HEX_ID} not found")

# Save metrics before reprojection
summary = target_hex.iloc[0]

# Map centering
center_geom = target_hex.geometry.centroid.iloc[0]

center_point = gpd.GeoSeries(
    [center_geom],
    crs=5070
).to_crs(4326)

center = [
    center_point.y.iloc[0],
    center_point.x.iloc[0]
]

target_hex_wgs84 = target_hex.to_crs(4326)

# ============================================================
# TARGET HEX + NEIGHBORS (STUDY AREA)
# ============================================================

study_hexes = gpd.read_postgis(
    f"""
    WITH target AS (
        SELECT *
        FROM analysis.hex_ne
        WHERE id = {HEX_ID}
    )

    SELECT
        h.*
    FROM analysis.hex_ne h
    JOIN target t
      ON ST_Touches(h.geom, t.geom)

    UNION

    SELECT *
    FROM target
    """,
    engine,
    geom_col="geom"
)

study_hexes_wgs84 = study_hexes.to_crs(4326)

print(f"Study Hex Count: {len(study_hexes)}")



# ============================================================
# ROADS
# ============================================================

roads = gpd.read_postgis(
    f"""
    WITH study_area AS (

        SELECT
            ST_Union(geom) AS geom
        FROM (

            SELECT h.geom
            FROM analysis.hex_ne h
            JOIN analysis.hex_ne t
            ON t.id = {HEX_ID}
            AND ST_Touches(h.geom, t.geom)

            UNION ALL

            SELECT geom
            FROM analysis.hex_ne
            WHERE id = {HEX_ID}

        ) x
    )

    SELECT
        r.segment_id,
        r.hydro_risk_score,
        r.dist_flowline,
        r.dist_waterbody,
        r.elevation,
        r.slope,

        ST_Intersection(
            rs.segment_geom,
            h.geom
        ) AS geom

    FROM analysis.road_hydro_features r

    JOIN analysis.road_segments rs
    USING (segment_id)

    CROSS JOIN study_area h

    WHERE ST_Intersects(
        rs.segment_geom,
        h.geom
    )
    """,
    engine,
    geom_col="geom"
)

roads = roads.to_crs(4326)

q20 = roads["hydro_risk_score"].quantile(0.20)
q40 = roads["hydro_risk_score"].quantile(0.40)
q60 = roads["hydro_risk_score"].quantile(0.60)
q80 = roads["hydro_risk_score"].quantile(0.80)

# ============================================================
# FLOWLINES
# ============================================================

flowlines = gpd.read_postgis(
    f"""
    WITH study_area AS (

        SELECT
            ST_Union(geom) AS geom
        FROM (

            SELECT h.geom
            FROM analysis.hex_ne h
            JOIN analysis.hex_ne t
                ON t.id = {HEX_ID}
            AND ST_Touches(h.geom, t.geom)

            UNION ALL

            SELECT geom
            FROM analysis.hex_ne
            WHERE id = {HEX_ID}

        ) x
    )

    SELECT
        f.objectid,
        f.ftype,
        f.fcode,

        ST_Intersection(
            f.geom,
            h.geom
        ) AS geom

    FROM prep.nhd_flowlines_ne f
    CROSS JOIN study_area h

    WHERE ST_Intersects(
        f.geom,
        h.geom
    )
    """,
    engine,
    geom_col="geom"
)

flowlines = flowlines.to_crs(4326)

# ============================================================
# WATERBODIES
# ============================================================

waterbodies = gpd.read_postgis(
    f"""
    WITH study_area AS (
        SELECT
            ST_Union(geom) AS geom
        FROM (

            SELECT h.geom
            FROM analysis.hex_ne h
            JOIN analysis.hex_ne t
                ON t.id = {HEX_ID}
            AND ST_Touches(h.geom, t.geom)

            UNION ALL

            SELECT geom
            FROM analysis.hex_ne
            WHERE id = {HEX_ID}

        ) x
    )

    SELECT
        w.objectid,
        w.ftype,
        w.fcode,

        ST_Intersection(
            w.geom,
            h.geom
        ) AS geom

    FROM prep.nhd_waterbodies_ne w
    CROSS JOIN study_area h

    WHERE ST_Intersects(
        w.geom,
        h.geom
    )
    """,
    engine,
    geom_col="geom"
)

waterbodies = waterbodies.to_crs(4326)

# ============================================================
# SLOPE RASTER
# ============================================================

import ast

with engine.connect() as conn:

   result = conn.execute(text(f"""

    WITH study_area AS (

        SELECT
            ST_Union(geom) AS geom

        FROM (

            SELECT h.geom
            FROM analysis.hex_ne h
            JOIN analysis.hex_ne t
            ON t.id = {HEX_ID}
            AND ST_Touches(h.geom, t.geom)

            UNION ALL

            SELECT geom
            FROM analysis.hex_ne
            WHERE id = {HEX_ID}

        ) x
    )

    SELECT
        ST_DumpValues(
            rast,
            1,
            false
        ),

        ST_UpperLeftX(rast),
        ST_UpperLeftY(rast),
        ST_Width(rast),
        ST_Height(rast),
        ST_ScaleX(rast),
        ST_ScaleY(rast)

    FROM (

        SELECT
            ST_Union(
                ST_Clip(
                    s.rast,
                    h.geom
                )
            ) AS rast

        FROM prep.dem_slope_ne s
        CROSS JOIN study_area h

        WHERE ST_Intersects(
            ST_ConvexHull(s.rast),
            h.geom
        )

    ) r

    """))

row = result.fetchone()


slope_values = row[0]

xmin = row[1]
ymax = row[2]

width = row[3]
height = row[4]

pixel_width = row[5]
pixel_height = row[6]

# Convert PostgreSQL array string to NumPy
slope_array = np.array(
    slope_values,
    dtype=float
)

# PostGIS nodata value
slope_array[
    slope_array == -999999.0
] = np.nan

# ============================================================
# REPROJECT RASTER FROM EPSG:5070 -> EPSG:4326
# ============================================================

src_transform = from_origin(
    xmin,
    ymax,
    pixel_width,
    abs(pixel_height)
)

src_crs = "EPSG:5070"
dst_crs = "EPSG:4326"

left = xmin
right = xmin + width * pixel_width

top = ymax
bottom = ymax + height * pixel_height

dst_transform, dst_width, dst_height = (
    calculate_default_transform(
        src_crs,
        dst_crs,
        width,
        height,
        left,
        bottom,
        right,
        top
    )
)

reprojected_slope = np.full(
    (dst_height, dst_width),
    np.nan,
    dtype=np.float32
)

reproject(
    source=slope_array,
    destination=reprojected_slope,
    src_transform=src_transform,
    src_crs=src_crs,
    src_nodata=np.nan,
    dst_transform=dst_transform,
    dst_crs=dst_crs,
    dst_nodata=np.nan,
    resampling=Resampling.bilinear
)

slope_array = reprojected_slope

print("Reprojected shape:", slope_array.shape)

vmin = np.nanpercentile(
    slope_array,
    2
)

vmax = np.nanpercentile(
    slope_array,
    98
)

norm = colors.Normalize(
    vmin=vmin,
    vmax=vmax
)

slope_rgba = cm.viridis(
    norm(slope_array)
)

# transparent nodata

slope_rgba[..., 3] = np.where(
    np.isnan(slope_array),
    0,
    1.0
)


# Raster bounds from metadata query

left = dst_transform.c

top = dst_transform.f

right = left + (
    dst_width * dst_transform.a
)

bottom = top + (
    dst_height * dst_transform.e
)

slope_bounds = [
    [bottom, left],
    [top, right]
]

# ============================================================
# MAP
# ============================================================

m = folium.Map(
    location=center,
    zoom_start=13,
    control_scale=True,
    tiles="OpenStreetMap"
)

# ============================================================
# SLOPE IMAGE OVERLAY
# ============================================================

ImageOverlay(
    image=slope_rgba,
    bounds=slope_bounds,
    opacity=0.5,
    name="Slope Raster"
).add_to(m)

# ============================================================
# SUMMARY PANEL
# ============================================================

summary_html = f"""
<div style="
position: fixed;
top: 10px;
left: 50px;
width: 300px;
z-index:9999;
background-color:white;
padding:10px;
border:2px solid #444;
font-size:13px;
">

<b>Target Hex Summary</b><br><br>

<b>Hex ID:</b> {HEX_ID}<br>
<b>Parent Avg Risk:</b> {summary.avg_hydro_risk:.2f}<br>
<b>Avg Flowline Dist:</b> {summary.avg_dist_flowline:.0f} m<br>
<b>Avg Waterbody Dist:</b> {summary.avg_dist_waterbody:.0f} m<br>
<b>Avg Elevation:</b> {summary.avg_elevation:.0f} m<br>
<b>Avg Slope:</b> {summary.avg_slope:.0f}<br>

</div>
"""

m.get_root().html.add_child(
    folium.Element(summary_html)
)

legend_html = f"""
<div style="
position: fixed;
top: 185px;
left: 50px;
width: 300px;
z-index:9998;
background-color:white;
padding:10px;
border:2px solid #444;
font-size:13px;
">

<b>Relative Road Flood Risk</b><br><br>

<div>
<span style="display:inline-block;width:18px;height:12px;background:#fee5d9;border:1px solid #333;"></span>
&nbsp; Very Low (&lt; {q20:.1f})
</div>

<div>
<span style="display:inline-block;width:18px;height:12px;background:#fcbba1;border:1px solid #333;"></span>
&nbsp; Low ({q20:.1f} - {q40:.1f})
</div>

<div>
<span style="display:inline-block;width:18px;height:12px;background:#fc9272;border:1px solid #333;"></span>
&nbsp; Moderate ({q40:.1f} - {q60:.1f})
</div>

<div>
<span style="display:inline-block;width:18px;height:12px;background:#ef3b2c;border:1px solid #333;"></span>
&nbsp; High ({q60:.1f} - {q80:.1f})
</div>

<div>
<span style="display:inline-block;width:18px;height:12px;background:#99000d;border:1px solid #333;"></span>
&nbsp; Very High (&gt; {q80:.1f})
</div>

</div>
"""

m.get_root().html.add_child(
    folium.Element(legend_html)
)

slope_legend_html = f"""
<div style="
position: fixed;
top: 420px;
left: 50px;
width: 300px;
z-index:9997;
background-color:white;
padding:10px;
border:2px solid #444;
font-size:13px;
">

<b>Slope (Degrees)</b><br><br>

<div style="
height:18px;
width:250px;
background: linear-gradient(
    to right,
    #440154,
    #3b528b,
    #21918c,
    #5ec962,
    #fde725
);
border:1px solid #333;
"></div>

<div style="
display:flex;
justify-content:space-between;
width:250px;
">

<span>{vmin:.1f}</span>
<span>{vmax:.1f}</span>

</div>

</div>
"""
m.get_root().html.add_child(
    folium.Element(slope_legend_html)
)

# ============================================================
# PARENT HEX
# ============================================================

parent_layer = folium.FeatureGroup(
    name="Parent 2km Hex",
    show=True
)

folium.GeoJson(
    target_hex_wgs84,
    style_function=lambda x: {
        "color": "Purple",
        "weight": 5,
        "fillOpacity": 0
    }
).add_to(parent_layer)

parent_layer.add_to(m)

# ============================================================
# NEIGHBOR HEXES
# ============================================================

# neighbor_layer = folium.FeatureGroup(
#     name="Neighbor 2km Hexes",
#     show=True
# )

# neighbors_only = study_hexes_wgs84[
#     study_hexes_wgs84["id"] != HEX_ID
# ]

# folium.GeoJson(
#     neighbors_only,
#     style_function=lambda x: {
#         "color": "#222222",
#         "weight": 2,
#         "fillOpacity": 0,
#         "dashArray": "5,5"
#     }
# ).add_to(neighbor_layer)

# neighbor_layer.add_to(m)

# ============================================================
# FLOWLINES
# ============================================================

flowline_layer = folium.FeatureGroup(
    name="Flowlines",
    show=True
)

folium.GeoJson(
    flowlines,
    style_function=lambda x: {
        "color": "#003C79",
        "weight": 2.5
    }
).add_to(flowline_layer)

flowline_layer.add_to(m)



# ============================================================
# WATERBODIES
# ============================================================

water_layer = folium.FeatureGroup(
    name="Waterbodies",
    show=True
)

folium.GeoJson(
    waterbodies,
    style_function=lambda x: {
        "color": "#003C79",
        "fillColor": "#003C79",
        "fillOpacity": 0.5,
        "weight": 1
    }
).add_to(water_layer)

water_layer.add_to(m)

# ============================================================
# ROADS
# ============================================================

road_layer = folium.FeatureGroup(
    name="Roads",
    show=True
)

folium.GeoJson(
    roads,
    style_function=lambda feature: {
        "color": "#333333",
        "weight": 6,
        "opacity": 0.8
    }
).add_to(road_layer)

folium.GeoJson(
    roads,
    style_function=lambda feature: {

        "color": road_color(
            feature["properties"]["hydro_risk_score"]
        ),

        "weight": 4,
        "opacity": 0.9

    },

    tooltip=folium.GeoJsonTooltip(
        fields=[
            "hydro_risk_score",
            "dist_flowline",
            "dist_waterbody",
            "elevation",
            "slope"
        ],

        aliases=[
            "Risk Score:",
            "Dist Flowline:",
            "Dist Waterbody:",
            "Elevation:",
            "Slope:"
        ]
    )
).add_to(road_layer)

road_layer.add_to(m)

# ============================================================
# CONTROLS
# ============================================================

folium.LayerControl(collapsed=False).add_to(m)
m.save(OUTPUT_HTML)
print(f"Saved: {OUTPUT_HTML}")