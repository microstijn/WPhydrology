using Rasters

paths = [
    "hydrology/discharge/discharge_monmean_m01.tif",
    "hydrology/rdepth/rdepth_monmean_m01.tif",
    "hydrology/river_restime/river_restime_monmean_m01.tif",
    "hydrology/runoff/runoff_daymonmean_m01.tif",
    "hydrology/routing/flowdir_ddm30_esri.tif"
]

for p in paths
    if isfile(p)
        println("--- Inspecting: ", p, " ---")
        r = Raster(p)
        println("Size: ", size(r))

        for d in dims(r)
            println(name(d), " axis:")
            println("  Type: ", typeof(d))
            println("  Length: ", length(d))
            println("  Range: ", first(d), " to ", last(d))
            println("  Step: ", step(d))

            lkp = lookup(d)
            println("  Order: ", order(lkp))
        end

        println("Missing val: ", missingval(r))
    end
end
