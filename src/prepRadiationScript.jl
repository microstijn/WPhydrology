# ==========================================
# GLOWPA FORCING PREP: SSRD & TEMPERATURE
# Reads existing Monthly NCs, averages to 12-month climatology,
# applies physics, and saves to Scenario folders.
# ==========================================
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Rasters, Dates, Statistics

# --- 1. DIRECTORIES ---
# Input folders for your already-processed monthly NetCDFs
dir_ssrd_monthly = raw"D:\WP\surfaceT\monthly"
dir_tas_monthly  = raw"C:\Users\peete074\Downloads\tas\monthly"

# The master output folder where your hydrology data already lives
glowpa_base_dir  = raw"C:\Users\peete074\Documents\hydroOut"

# --- 2. MASTER GRID ---
println("Loading Master Grid...")
master_grid_path = raw"C:\Users\peete074\Documents\hydroOut\routing\flowdir.tif"
fd_master = Raster(master_grid_path)

# Ensure North-Up orientation
y_coords = lookup(fd_master, Y)
if y_coords[1] < y_coords[end]
    println("🔄 Flipping Master Grid to North-Up...")
    fd_master = reverse(fd_master, dims=Y)
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

    for file in monthly_files
        # --- A. EXACT SCENARIO MATCHING ---
        # e.g., "rsds_monthly_GFDL-ESM4_ssp126_2021_2030.nc" -> "GFDL-ESM4_ssp126_2021_2030"
        scenario_name = replace(file, prefix_to_remove => "")
        scenario_name = replace(scenario_name, ".nc" => "")

        println("\n=== Processing $var_name for Scenario: $scenario_name ===")

        # Target folder (e.g., D:\WPhydrologyOut\GFDL-ESM4_ssp126_2021_2030\ssrd\)
        folder_name = var_name == "rsds" ? "ssrd" : "river_temperature"
        out_dir_glowpa = joinpath(glowpa_base_dir, scenario_name, folder_name)
        mkpath(out_dir_glowpa)

        # Load the 10-year monthly NetCDF
        in_path = joinpath(input_dir, file)
        nc_raster = Raster(in_path, name=var_name)
        times = lookup(nc_raster, Ti)

        println("   Averaging 10 years to 12-month climatology, aligning, and applying physics...")

        # --- B. 12-MONTH CLIMATOLOGY & PHYSICS ---
        for m in 1:12
            # Find all Januarys, Februarys, etc., across the 10 years
            month_indices = findall(dt -> Dates.month(dt) == m, times)

            # Calculate the mean for this specific month
            month_avg = mean(nc_raster[Ti(month_indices)], dims=Ti)
            month_2d = dropdims(month_avg, dims=Ti)

            # Resample to perfect routing grid alignment
            aligned = resample(month_2d, to=fd_master)

            final_data = nothing

            # --- PHYSICS FILTERS ---
            if var_name == "rsds"
                # SSRD: W/m² to kJ/m²/day
                final_data = aligned .* 86.4f0

            elseif var_name == "tas"
                # TAS: Kelvin to Celsius (Floor at 0.0°C)
                final_data = map(aligned) do val
                    if ismissing(val) || isnan(val)
                        return missing
                    else
                        celsius = val - 273.15f0
                        return max(celsius, 0.0f0)
                    end
                end
            end

            # Replace missing with -9999.0
            data_clean = replace_missing(final_data, -9999.0f0)

            # Format filename (e.g., ssrd_m01.tif)
            month_str = lpad(m, 2, "0")
            file_prefix = var_name == "rsds" ? "ssrd" : "river_temperature"
            out_file = joinpath(out_dir_glowpa, "$(file_prefix)_m$(month_str).tif")

            # Save
            write(out_file, data_clean, force=true)
        end
        println("   ✅ Saved 12 monthly files to $out_dir_glowpa")
    end
end

# ==========================================
# 3. RUN PROCESSES
# ==========================================
println("\n🌞 STARTING SOLAR RADIATION (SSRD) PREP...")
# IMPORTANT: Adjust "rsds_monthly_" if your actual file prefix is different!
process_glowpa_variable(dir_ssrd_monthly, "rsds", "rsds_monthly_")

println("\n🌡️ STARTING RIVER TEMPERATURE PREP...")
# IMPORTANT: Adjust "tas_monthly_" if your actual file prefix is different!
process_glowpa_variable(dir_tas_monthly, "tas", "tas_monthly_")

println("\n🎉 All SSRD and Temperature files processed and merged into hydrology folders!")