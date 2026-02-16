
# load environment
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# set data folder
dataFolder = raw"D:\OneDrive_1_12-2-2026"

# set packages
using WPhydrology
using Rasters, Dates

# set filenames
f_runoff    = "monthly_runoff_GFDL-ESM4_ssp126_2015_2020.nc.txt"
f_baseflow  = "monthly_baseflow_GFDL-ESM4_ssp126_2015_2020.nc.txt"
f_discharge = "monthly_discharge_GFDL-ESM4_ssp126_2015_2020.nc.txt"
f_flowdir   = raw"D:\OneDrive_1_12-2-2026\ddm30_flowdir_cru_neva.nc"

# set output folder 
out_dir = raw"D:\WPhydrologyOut"
mkpath(joinpath(out_dir, "routing"))


#=
    Running the actual stuff
    We have the output of VIC as made monthly by Mengru
    These are not traditional netcdf files. They are instead tabular data a xy coords + date
    for each monthy value. We therefore have to for each month have a vector of values. 

    IO module
    designed to return a vector of rasters from the monthly txt files

    routing
    calculates flow accumulation. Is based on VIC input file (and does not require the monthly outputs)

    hydraulics module
    takes all our data (runoff, baseflow, discharge, routing) to produce runoff rate, depth and residence time. 
=#

# routing 
# first we load the flowdir raster. 
using NCDatasets

fd_master = Raster(f_flowdir) 

# I noticed the y direction can be flipped. To ensure we have the Glowpa desired orientation
# which is north up I added this check. 
y_coords = lookup(fd_master, Y)
if y_coords[1] < y_coords[end]
    fd_master = reverse(fd_master, dims=Y)
    write(joinpath(out_dir, "routing", "flowdir.tif"), fd_master)
end
# flow accumlation from VIC input
# need archdal to write to file
acc = compute_flow_accumulation(fd_master)
using ArchGDAL
write(joinpath(out_dir, "routing", "flowacc.tif"), acc)

# Load and parse
# runoff
ts_runoff = parse_climate_timeseries(
    joinpath(dataFolder, f_runoff),
    fd_master
)

# baseflow
ts_baseflow  = parse_climate_timeseries(
    joinpath(dataFolder, f_baseflow),
    fd_master
)

# discharge
ts_discharge = parse_climate_timeseries(
    joinpath(dataFolder, f_discharge),
    fd_master
)

# checks to ensure similar sizes 
# if they do not match the next loop wont work. 
if length(ts_runoff) != length(ts_baseflow) || length(ts_runoff) != length(ts_discharge)
    error(
        "Mismatch in number of months! Runoff: $(length(ts_runoff)),
        Baseflow: $(length(ts_baseflow))"
    )
end

# loop over runoff as base grid. 
# ensure dates match each other. 
# Determine runoff, depth, discargresidence time from our loaded rasters.
# write tifs to file as that is what glowpa uses as input. 
for i in 1:length(ts_runoff)
    # Get the data for this step
    date_step = ts_runoff[i].date
    
    # Double check dates match across files
    if date_step != ts_baseflow[i].date
        println("Warning: Date mismatch at index $i! $(date_step) vs $(ts_baseflow[i].date)")
    end
    
    # Format YYYY_MM string for filename
    date_str = Dates.format(date_step, "yyyy_mm")
    
    r_val = ts_runoff[i].raster
    b_val = ts_baseflow[i].raster
    q_val = ts_discharge[i].raster
    
    # Get exact days for this specific month (Handling Leap Years!)
    days = daysinmonth(date_step)
    
    # Compute
    ro_out, dep_out, res_out = compute_glowpa_month(r_val, b_val, q_val, fd_master, days)
    
    # Save with YYYY_MM pattern
    # Not sure glowpa will take it, but will update when i try
    paths = [
        "runoff/runoff_$(date_str).tif",
        "discharge/discharge_$(date_str).tif",
        "river_depth/river_depth_$(date_str).tif",
        "river_restime/river_restime_$(date_str).tif"
    ]
    
    for p in paths; mkpath(joinpath(out_dir, dirname(p))); end
    
    write(joinpath(out_dir, paths[1]), ro_out, force=true)
    write(joinpath(out_dir, paths[2]), q_val, force=true)
    write(joinpath(out_dir, paths[3]), dep_out, force=true)
    write(joinpath(out_dir, paths[4]), res_out, force=true)
    
    println("   Saved $date_str")

end


