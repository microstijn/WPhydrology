import rasterio

paths = [
    "hydrology/discharge/discharge_monmean_m01.tif",
    "hydrology/rdepth/rdepth_monmean_m01.tif",
    "hydrology/river_restime/river_restime_monmean_m01.tif",
    "hydrology/runoff/runoff_daymonmean_m01.tif"
]

for p in paths:
    try:
        with rasterio.open(p) as src:
            print(f"--- {p} ---")
            print(f"Size: {src.width} x {src.height}")
            print(f"Bounds: {src.bounds}")
            print(f"Transform: {src.transform}")
            print(f"CRS: {src.crs}")
            print(f"NoData: {src.nodata}")
            print(f"Dtypes: {src.dtypes}")

            # Read first band and get min/max
            band1 = src.read(1)
            valid_mask = band1 != src.nodata
            if valid_mask.any():
                print(f"Min: {band1[valid_mask].min()}, Max: {band1[valid_mask].max()}")
            else:
                print("Min/Max: Empty")
            print()
    except Exception as e:
        print(f"Error reading {p}: {e}")
