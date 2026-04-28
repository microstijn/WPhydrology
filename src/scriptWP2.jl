# ==========================================
# MASTER GLOWPA HYDROLOGY PREP SCRIPT
# ==========================================
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

# Load necessary packages
using WPhydrology
using Rasters, Dates, Statistics
using ArchGDAL
using NCDatasets
using Base.Threads
# Set directories

dataFolder = raw"C:\Users\peete074\Documents\hydro"
out_dir    = raw"C:\Users\peete074\Documents\hydroOut"

# ==========================================
# 1. ROUTING (Static Map Prep)
# ==========================================
println("Setting up Master Routing Grid...")
f_flowdir = joinpath(dataFolder, raw"D:\WPhydrologyOut\routing\flowdir.tif")
fd_master = Raster(f_flowdir)

# Ensure North-Up orientation for GloWPa
y_coords = lookup(fd_master, Y)
if y_coords[1] < y_coords[end]
    println("🔄 Flipping Master Grid to North-Up...")
    fd_master = reverse(fd_master, dims=Y)
end

# Create routing output folder and save
routing_dir = joinpath(out_dir, "routing")
mkpath(routing_dir)
write(joinpath(routing_dir, "flowdir.tif"), fd_master)

# Compute flow accumulation from VIC input
println("Computing flow accumulation...")
acc = compute_flow_accumulation(fd_master)
write(joinpath(routing_dir, "flowacc.tif"), acc)

# ==========================================
# 2. SCENARIO PROCESSING LOOP
# ==========================================
# Find all runoff files to act as our scenario "anchors"
all_files = readdir(dataFolder)
runoff_files = filter(f -> startswith(f, "monthly_runoff") && endswith(f, ".nc.txt"), all_files)

# Create a lock for clean console output during multithreading
io_lock = ReentrantLock()

println("\n🚀 Starting multithreaded processing across $(Threads.nthreads()) threads...")

Threads.@threads for r_file in runoff_files
    # --- A. Extract Scenario Name ---
    # Removes the prefix and suffix to isolate the exact Model_SSP_Decade string
    scenario_name = replace(r_file, "monthly_runoff_" => "")
    scenario_name = replace(scenario_name, ".nc.txt" => "")

    lock(io_lock) do
        println("\n=== Processing Scenario: $scenario_name ===")
    end

    # --- B. Find Matching Variable Files ---
    b_file = replace(r_file, "monthly_runoff" => "monthly_baseflow")
    q_file = replace(r_file, "monthly_runoff" => "monthly_discharge")

    if !isfile(joinpath(dataFolder, b_file)) || !isfile(joinpath(dataFolder, q_file))
        lock(io_lock) do
            println("   ❌ Missing matching baseflow or discharge for $scenario_name. Skipping.")
        end
        continue
    end

    # --- C. Load and Parse ---
    lock(io_lock) do
        println("   Parsing text files for $scenario_name...")
    end
    
    ts_runoff    = parse_climate_timeseries(joinpath(dataFolder, r_file), fd_master)
    ts_baseflow  = parse_climate_timeseries(joinpath(dataFolder, b_file), fd_master)
    ts_discharge = parse_climate_timeseries(joinpath(dataFolder, q_file), fd_master)

    # Sanity check
    if length(ts_runoff) != length(ts_baseflow) || length(ts_runoff) != length(ts_discharge)
        error("   ❌ Mismatch in number of months between variables for $scenario_name!")
    end

    # --- D. 12-Month Climatology & Hydraulics ---
    lock(io_lock) do
        println("   Averaging to 12-month climatology and calculating hydraulics for $scenario_name...")
    end

    # Create scenario-specific output folders
    out_dir_scenario = joinpath(out_dir, scenario_name)
    paths = ["runoff", "discharge", "river_depth", "river_restime"]
    for p in paths
        mkpath(joinpath(out_dir_scenario, p))
    end

    # Loop exactly 12 times (January through December)
    for m in 1:12
        # Find all time indices that match this specific month across the 10 years
        month_indices = findall(x -> Dates.month(x.date) == m, ts_runoff)

        # Average the rasters for this month across all years
        r_avg = mean([ts_runoff[idx].raster for idx in month_indices])
        b_avg = mean([ts_baseflow[idx].raster for idx in month_indices])
        q_avg = mean([ts_discharge[idx].raster for idx in month_indices])

        # Get days in this month
        days = daysinmonth(Date(2015, m, 1))

        # Compute hydraulics
        ro_out, dep_out, res_out = compute_glowpa_month(r_avg, b_avg, q_avg, fd_master, days)

        ro_out  = format_for_glowpa(ro_out)
        q_avg   = format_for_glowpa(q_avg)
        dep_out = format_for_glowpa(dep_out)
        res_out = format_for_glowpa(res_out)

        # Format string strictly as m01, m02 for GloWPa-R
        month_str = lpad(m, 2, "0")

        # Save to the scenario folder
        write(joinpath(out_dir_scenario, "runoff", "runoff_m$(month_str).tif"), ro_out, force=true)
        write(joinpath(out_dir_scenario, "discharge", "discharge_m$(month_str).tif"), q_avg, force=true)
        write(joinpath(out_dir_scenario, "river_depth", "river_depth_m$(month_str).tif"), dep_out, force=true)
        write(joinpath(out_dir_scenario, "river_restime", "river_restime_m$(month_str).tif"), res_out, force=true)
    end

    lock(io_lock) do
        println("   ✅ Saved 12 monthly climatology files to $out_dir_scenario")
    end
end

println("\n🎉 All hydrology scenarios processed and separated successfully!")