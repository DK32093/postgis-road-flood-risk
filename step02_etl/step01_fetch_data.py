import os
import requests
from dotenv import load_dotenv
import geopandas as gpd
import cartopy.io.shapereader as shpreader

load_dotenv()

DATA_DIR = "data/raw"
os.makedirs(DATA_DIR, exist_ok=True)

VECTOR_DATASETS = {
    "osm": {
        "url": "https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf",
        "filename": "osm_roads_northeast.osm.pbf",
        "label": "OSM Northeast Roads"
    },
    "nhd": {
        "url": "https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHDPlusHR/VPU/Current/GDB/NHDPLUS_H_0101_HU4_20220901_GDB.zip",
        "filename": "nhd_new_england.zip",
        "label": "NHDPlus HR New England (HUC01)"
    }
}

RASTER_DATASETS = {
    "dem": {
        "endpoint": "https://portal.opentopography.org/API/usgsdem",
        "dataset": "USGS30m",
        "bbox": { # From the state boundaries of the six New England states
            "south": 40.991860,
            "north": 47.462995,
            "west": -73.723015,
            "east": -66.987022
        },
        "label": "USGS 30m DEM"
    }
}

STATE_BOUNDARIES = {
    "NE": {
        "name": "admin_1_states_provinces",
        "category": "cultural",
        "resolution": "50m",
        "codes": ["US-ME", "US-NH", "US-VT", "US-MA", "US-CT", "US-RI"]
    }
}

def fetch_state_boundaries():
    for key, meta in STATE_BOUNDARIES.items():
        shp_path = shpreader.natural_earth(
            resolution=meta["resolution"],
            category=meta["category"],
            name=meta["name"]
        )
        gdf = gpd.read_file(shp_path)
        gdf_aoi = gdf[gdf["iso_3166_2"].isin(meta["codes"])].copy()
        out_path = os.path.join(DATA_DIR, f"{key}_state_boundaries.shp")
        gdf_aoi.to_file(out_path)
        print(f"Saved {key} state boundaries to {out_path}")

def fetch_vector_data():
    for key, meta in VECTOR_DATASETS.items():
        url = meta["url"]
        out_path = os.path.join(DATA_DIR, meta["filename"])
        label = meta["label"]

        print(f"Fetching {label}...")
        r = requests.get(url, stream=True)
        r.raise_for_status()

        with open(out_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)

        print(f"Saved {label} to {out_path}")

# Tile the DEM bounding box to allow smaller requests to the OpenTopography API
def split_bbox(bbox, n_rows=4, n_cols=4):
    south, north = bbox["south"], bbox["north"]
    west, east = bbox["west"], bbox["east"]

    dlat = (north - south) / n_rows
    dlon = (east - west) / n_cols

    tiles = []
    for i in range(n_rows):
        for j in range(n_cols):
            tile_south = south + i * dlat
            tile_north = tile_south + dlat
            tile_west = west + j * dlon
            tile_east = tile_west + dlon
            tiles.append({
                "south": tile_south,
                "north": tile_north,
                "west": tile_west,
                "east": tile_east,
            })

    return tiles

def fetch_raster_data():
    for key, meta in RASTER_DATASETS.items():
        api_key = os.getenv("OPENTOPO_API_KEY")
        if not api_key:
            raise RuntimeError("Missing OpenTopography API key in .env")

        dataset = meta["dataset"]
        bbox = meta["bbox"]
        url = meta["endpoint"]

        tiles = split_bbox(bbox, n_rows=2, n_cols=3)

        for idx, tb in enumerate(tiles):
            params = {
                "datasetName": dataset,
                "south": tb["south"],
                "north": tb["north"],
                "west": tb["west"],
                "east": tb["east"],
                "outputFormat": "GTiff",
                "API_Key": api_key
            }

            out_path = os.path.join(DATA_DIR, f"{dataset}_NE_tile_{idx}.tif")
            print(f"Fetching {meta['label']} tile {idx}...")
            r = requests.get(url, params=params, stream=True)
            r.raise_for_status()

            with open(out_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)

            print(f"Saved DEM tile {idx} to {out_path}")

if __name__ == "__main__":
    fetch_state_boundaries()
    fetch_vector_data()
    fetch_raster_data()
