# ==========================================
# GLOWPA FORCING PREP: SSRD & TEMPERATURE
# Reads existing Monthly NCs, averages to 12-month climatology,
# applies physics, pads to global grid, and saves to Scenario folders.
# ==========================================

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Rasters, Dates, Statistics
using DimensionalData.Dimensions.Lookups # explicit loading into namespace as it is not automatically imported by Rasters
using Base.Threads # For multithreading
import ArchGDAL # For resampling with locking

# DIRECTORIES
# Input folders for your already-processed monthly NetCDFs
dir_ssrd_monthly = raw"D:\WP\surfaceT\monthly"
dir_tas_monthly  = raw"C:\Users\peete074\Downloads\tas\monthly"

# The master output folder where the hydrology data already lives
glowpa_base_dir  = raw"C:\Users\peete074\Documents\hydroOut"

# MASTER GRID to hang everything on (should already be saved from routing prep)
master_grid_path = joinpath(glowpa_base_dir, "routing", "flowdir.tif")
fd_master = read(Raster(master_grid_path))

# Ensure North-Up orientation as GloWPa requires
y_coords = lookup(fd_master, Y)
if y_coords[1] < y_coords[end]
    println("🔄 Flipping Master Grid to North-Up...")
    fd_master = reverse(fd_master, dims=Y)
end

# ==========================================
# FUNCTION: Format to Global Standard
# ==========================================
"""
    format_for_glowpa(r::Raster)
Dynamically pads a cropped raster into a full global 720x360 raster,
shifts the coordinate lookups to Intervals(Start()), and ensures
missing values are strictly recorded as `missing`.
"""
function format_for_glowpa(r::Raster)
    y_lookups = lookup(r, Y)
    res = abs(step(y_lookups))
    
    top_edge = first(y_lookups) + (res / 2.0)
    row_start = round(Int, (90.0 - top_edge) / res) + 1
    row_end   = row_start + size(r, Y) - 1

    global_data = Matrix{Union{Float32, Missing}}(missing, 720, 360)
    clean_data = map(x -> isnothing(x) || isnan(x) ? missing : Float32(x), r)
    global_data[:, row_start:row_end] .= clean_data

    x_dim = X(range(-180.0, step=0.5, length=720); sampling=Intervals(Start()))
    y_dim = Y(range(89.5, step=-0.5, length=360); sampling=Intervals(Start()))

    return Raster(global_data, (x_dim, y_dim); missingval=missing)
end


# ==========================================
# FUNCTION: Process a variable
# ==========================================
function process_glowpa_variable(input_dir, var_name, prefix_to_remove)
    monthly_files = filter(f -> endswith(f, ".nc"), readdir(input_dir))

    if isempty(monthly_files)
        println("⚠️ No files found in $input_dir")
        return
    end

    Threads.@threads for file in monthly_files
        # Scenario matching
        scenario_name = replace(file, prefix_to_remove => "")
        scenario_name = replace(scenario_name, ".nc" => "")

        lock(io_lock) do
            println("\n=== Processing $var_name for Scenario: $scenario_name ===")
        end

        # Target folder inside the existing scenario directory
        folder_name = var_name == "rsds" ? "ssrd" : "river_temperature"
        out_dir_glowpa = joinpath(glowpa_base_dir, scenario_name, folder_name)
        mkpath(out_dir_glowpa)

        # Load the 10-year monthly NetCDF
        in_path = joinpath(input_dir, file)
        
        nc_raster = try
            Raster(in_path, name=var_name)
        catch e
            lock(io_lock) do
                println("   ❌ CORRUPT FILE DETECTED: Skipping $file (Error -51)")
            end
            continue # Abort this specific file and move to the next one
        end
        
        times = lookup(nc_raster, Ti)

        # 12-month climatology loop
        for m in 1:12
            month_indices = findall(dt -> Dates.month(dt) == m, times)

            # Calculate the mean for this specific month
            month_avg = mean(nc_raster[Ti(month_indices)], dims=Ti)
            month_2d = dropdims(month_avg, dims=Ti)

            # Resample to perfect routing grid alignment
            aligned = lock(gdal_lock) do
                resample(month_2d, to=fd_master)
            end

            final_data = nothing

            # PHYSICS ADJUSTMENTS
            if var_name == "rsds"
                # SSRD: W/m² to kJ/m²/day
                final_data = aligned .* 86.4f0

            elseif var_name == "tas"
                # TAS: Kelvin to Celsius (Floor at 0.0°C)
                final_data = map(aligned) do val
                    if ismissing(val) || isnan(val)
                        return missing
                    else
                        return max(val - 273.15f0, 0.0f0)
                    end
                end
            end

            # FORMAT TO GLOBAL 360-ROW GRID
            data_clean = format_for_glowpa(final_data)

            # Format filename (e.g., triver_m01.tif or ssrd_m01.tif)
            month_str = lpad(m, 2, "0")
            
            # Changed to `triver` to match logs
            file_prefix = var_name == "rsds" ? "ssrd" : "triver" 
            out_file = joinpath(out_dir_glowpa, "$(file_prefix)_m$(month_str).tif")

            # Save
            write(out_file, data_clean, force=true)
        end
        
        lock(io_lock) do
            println("   ✅ Saved 12 monthly files to $out_dir_glowpa")
        end
    end
end

# ==========================================
# 3. RUN PROCESSES
# ==========================================

# Create a lock for clean console output
io_lock = ReentrantLock()
gdal_lock = ReentrantLock()

println("\n🌞 PROCESSING SOLAR RADIATION (SSRD)...")
process_glowpa_variable(dir_ssrd_monthly, "rsds", "rsds_monthly_")

println("\n🌡️ PROCESSING RIVER TEMPERATURE (TAS)...")
process_glowpa_variable(dir_tas_monthly, "tas", "tas_monthly_")

println("\n🎉 All SSRD and Temperature files processed, formatted, and merged into hydrology folders!")