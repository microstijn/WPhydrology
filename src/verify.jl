using Rasters
using Dates
using Test

"""
    verify_output(generated_path::String, expected_path::String)
Compares a generated raster against the expected "correct" raster.
Reports mismatches in dimensions, resolution, extent, and value ranges.
"""
function verify_output(generated_path::String, expected_path::String)
    println("---------------------------------------------------------")
    println("Verifying: ", basename(generated_path))
    println("Expected : ", expected_path)

    if !isfile(generated_path)
        println("  ❌ ERROR: Generated file not found.")
        return false
    end
    if !isfile(expected_path)
        println("  ❌ ERROR: Expected file not found.")
        return false
    end

    r_gen = Raster(generated_path)
    r_exp = Raster(expected_path)

    passed = true

    # 1. Dimensions
    if size(r_gen) != size(r_exp)
        println("  ❌ Dimension mismatch: Generated $(size(r_gen)) vs Expected $(size(r_exp))")
        passed = false
    else
        println("  ✅ Dimensions match: $(size(r_exp))")
    end

    # 2. X and Y Extent and resolution
    try
        x_gen = lookup(r_gen, X)
        x_exp = lookup(r_exp, X)
        y_gen = lookup(r_gen, Y)
        y_exp = lookup(r_exp, Y)

        # Check resolution
        res_x_gen = step(x_gen)
        res_x_exp = step(x_exp)
        if !(res_x_gen ≈ res_x_exp)
            println("  ❌ X Resolution mismatch: Generated $(res_x_gen) vs Expected $(res_x_exp)")
            passed = false
        end

        res_y_gen = step(y_gen)
        res_y_exp = step(y_exp)
        if !(res_y_gen ≈ res_y_exp)
            println("  ❌ Y Resolution mismatch: Generated $(res_y_gen) vs Expected $(res_y_exp)")
            passed = false
        end

        # Check Extent
        if !(first(x_gen) ≈ first(x_exp)) || !(last(x_gen) ≈ last(x_exp))
            println("  ❌ X Extent mismatch: Generated [$(first(x_gen)), $(last(x_gen))] vs Expected [$(first(x_exp)), $(last(x_exp))]")
            passed = false
        end

        if !(first(y_gen) ≈ first(y_exp)) || !(last(y_gen) ≈ last(y_exp))
            println("  ❌ Y Extent mismatch: Generated [$(first(y_gen)), $(last(y_gen))] vs Expected [$(first(y_exp)), $(last(y_exp))]")
            passed = false
        end

        # Check Axis Flipping (Order)
        # Use DimensionalData.order to avoid collision with DataFrames.order
        if DimensionalData.order(x_gen) != DimensionalData.order(x_exp)
            println("  ❌ X Axis Order mismatch: Generated $(DimensionalData.order(x_gen)) vs Expected $(DimensionalData.order(x_exp))")
            passed = false
        end
        if DimensionalData.order(y_gen) != DimensionalData.order(y_exp)
            println("  ❌ Y Axis Order mismatch: Generated $(DimensionalData.order(y_gen)) vs Expected $(DimensionalData.order(y_exp))")
            passed = false
        end

    catch e
        println("  ❌ Error checking spatial lookups (axes might be missing): ", e)
        passed = false
    end


    # 3. Missing Value Types
    mv_gen = missingval(r_gen)
    mv_exp = missingval(r_exp)
    
    if isnothing(mv_gen) && isnothing(mv_exp)
        println("  ✅ Missing values match (both 'nothing')")
    elseif ismissing(mv_gen) && ismissing(mv_exp)
        println("  ✅ Missing values match (both 'missing')")
    elseif (mv_gen isa Number && isnan(mv_gen)) && (mv_exp isa Number && isnan(mv_exp))
        println("  ✅ Missing values match (both 'NaN')")
    elseif !isequal(mv_gen, mv_exp)
        println("  ⚠️ Warning: Missing value mismatch: Generated $(mv_gen) vs Expected $(mv_exp)")
    end

    # 4. Values (Min/Max and Distribution)
    vals_gen = collect(skipmissing(r_gen))
    vals_exp = collect(skipmissing(r_exp))

    if isempty(vals_gen) && isempty(vals_exp)
        println("  ✅ Both rasters are empty (only missing values).")
    elseif isempty(vals_gen) && !isempty(vals_exp)
        println("  ❌ Generated raster is empty but Expected is not.")
        passed = false
    elseif !isempty(vals_gen) && isempty(vals_exp)
        println("  ❌ Expected raster is empty but Generated is not.")
        passed = false
    else
        # Remove NaNs from vals if any sneaked past skipmissing
        vals_gen = filter(!isnan, vals_gen)
        vals_exp = filter(!isnan, vals_exp)

        min_g, max_g = isempty(vals_gen) ? (NaN, NaN) : extrema(vals_gen)
        min_e, max_e = isempty(vals_exp) ? (NaN, NaN) : extrema(vals_exp)

        println("  📊 Generated Extrema: Min = $(min_g), Max = $(max_g)")
        println("  📊 Expected Extrema : Min = $(min_e), Max = $(max_e)")

        # Check if ranges are completely disjoint or significantly off
        # (This is a heuristic check, since we don't know if the dates/models exactly match)
        if min_g > max_e * 10 || max_g < min_e / 10
            println("  ❌ Values are drastically different in scale.")
            passed = false
        end
    end

    println(passed ? "  ✅ VERIFICATION PASSED" : "  ❌ VERIFICATION FAILED")
    return passed
end

"""
    run_all_verifications(generated_dir, expected_dir, date_str, month_str)
Runs verification for runoff, discharge, river_depth, and river_restime.
"""
function run_all_verifications(generated_dir::String, expected_dir::String, date_str::String, month_str::String)
    println("\n=========================================================")
    println("STARTING VERIFICATION FOR DATE: ", date_str)
    println("=========================================================")

    # Define paths
    paths = [
        (
            joinpath(generated_dir, "runoff", "runoff_$(date_str).tif"),
            joinpath(expected_dir, "runoff", "runoff_daymonmean_$(month_str).tif")
        ),
        (
            joinpath(generated_dir, "discharge", "discharge_$(date_str).tif"),
            joinpath(expected_dir, "discharge", "discharge_monmean_$(month_str).tif")
        ),
        (
            joinpath(generated_dir, "river_depth", "river_depth_$(date_str).tif"),
            joinpath(expected_dir, "rdepth", "rdepth_monmean_$(month_str).tif")
        ),
        (
            joinpath(generated_dir, "river_restime", "river_restime_$(date_str).tif"),
            joinpath(expected_dir, "river_restime", "river_restime_monmean_$(month_str).tif")
        )
    ]

    all_passed = true
    for (gen_path, exp_path) in paths
        if !verify_output(gen_path, exp_path)
            all_passed = false
        end
    end

    println("\n=========================================================")
    println(all_passed ? "🎉 ALL VERIFICATIONS PASSED" : "🛑 SOME VERIFICATIONS FAILED")
    println("=========================================================\n")
    return all_passed
end

"""
    verify_scenario_month(scenario_dir, expected_dir, month_str)
Runs verification for runoff, discharge, river_depth, and river_restime for a specific month.
"""
function verify_scenario_month(scenario_dir::String, expected_dir::String, month_str::String)

    
    # Define paths based on your new clean output structure
    paths = [
        (
            joinpath(scenario_dir, "runoff", "runoff_$(month_str).tif"),
            joinpath(expected_dir, "runoff", "runoff_daymonmean_$(month_str).tif")
        ),
        (
            joinpath(scenario_dir, "discharge", "discharge_$(month_str).tif"),
            joinpath(expected_dir, "discharge", "discharge_monmean_$(month_str).tif")
        ),
        (
            joinpath(scenario_dir, "river_depth", "river_depth_$(month_str).tif"),
            joinpath(expected_dir, "rdepth", "rdepth_monmean_$(month_str).tif") # Note the rdepth folder name!
        ),
        (
            joinpath(scenario_dir, "river_restime", "river_restime_$(month_str).tif"),
            joinpath(expected_dir, "river_restime", "river_restime_monmean_$(month_str).tif")
        )
    ]

    all_passed = true
    for (gen_path, exp_path) in paths
        if !verify_output(gen_path, exp_path)
            all_passed = false
        end
    end
    return all_passed
end


"""
    run_batch_verifications(generated_base_dir, expected_dir)
Finds all scenario folders and verifies all 12 months for each.
"""
function run_batch_verifications(generated_base_dir::String, expected_dir::String)
    # Get all items in the generated directory
    items = readdir(generated_base_dir, join=true)
    
    # Filter for directories, and explicitly ignore the "routing" static map folder
    scenario_dirs = filter(x -> isdir(x) && basename(x) != "routing", items)

    if isempty(scenario_dirs)
        println("❌ No scenario folders found in $generated_base_dir")
        return
    end

    total_scenarios = length(scenario_dirs)
    failed_scenarios = String[]

    println("\n🚀 STARTING BATCH VERIFICATION FOR $total_scenarios SCENARIOS")

    for scenario_dir in scenario_dirs
        scenario_name = basename(scenario_dir)
        println("\n=========================================================")
        println("🔍 SCENARIO: $scenario_name")
        println("=========================================================")

        scenario_passed = true

        # Loop through months 1 to 12
        for m in 1:12
            month_str = "m" * lpad(m, 2, "0") # Formats as m01, m02, etc.
            
            println("\n--- Checking Month: $month_str ---")
            month_passed = verify_scenario_month(scenario_dir, expected_dir, month_str)
            
            if !month_passed
                scenario_passed = false
            end
        end

        if !scenario_passed
            push!(failed_scenarios, scenario_name)
        end
    end

    # --- Final Batch Summary ---
    println("\n=========================================================")
    println("📊 BATCH VERIFICATION SUMMARY")
    println("=========================================================")
    if isempty(failed_scenarios)
        println("🎉 PERFECT RUN! All $(total_scenarios) scenarios passed completely.")
    else
        println("🛑 SOME FAILURES DETECTED.")
        println("   Passed: $(total_scenarios - length(failed_scenarios))")
        println("   Failed: $(length(failed_scenarios))")
        println("\nScenarios with errors:")
        for failed in failed_scenarios
            println("  - $failed")
        end
    end
    println("=========================================================\n")
end


# ==========================================
# EXECUTION BLOCK
# ==========================================

# Edit these default paths to match your current system
gen_base_dir = raw"C:\Users\peete074\Documents\hydroOut"
exp_dir      = joinpath(@__DIR__, "..", "hydrology")
# Override via command line if needed
if length(ARGS) >= 2
    gen_base_dir = ARGS[1]
    exp_dir      = ARGS[2]
end
run_batch_verifications(gen_base_dir, exp_dir)







# Default parameters based on scriptWP.jl layout
gen_dir = raw"C:\Users\peete074\Documents\hydroOut"
exp_dir = joinpath(@__DIR__, "..", "hydrology")
# Check if user provided arguments
if length(ARGS) >= 2
    gen_dir = ARGS[1]
    exp_dir = ARGS[2]
end
# For testing, we can check 2015_01 against m01
date_str = length(ARGS) >= 3 ? ARGS[3] : "2021_01"
month_str = length(ARGS) >= 4 ? ARGS[4] : "m01"
import ArchGDAL
run_all_verifications(gen_dir, exp_dir, date_str, month_str)


# Edit these to point exactly to wherever your current test files are sitting.
gen_file = raw"C:\Users\peete074\Documents\hydroOut\GFDL-ESM4_ssp126_2021_2030\runoff\runoff_m02.tif" # Example: wherever it actually landed
exp_file = joinpath(@__DIR__, "..", "hydrology", "runoff", "runoff_daymonmean_m01.tif")
# 2. Allow overriding via command line arguments so you can quickly test different 
# files from the terminal without editing the script every time.
if length(ARGS) >= 2
    gen_file = ARGS[1]
    exp_file = ARGS[2]
end

# Run the check on just this single pair
verify_output(gen_file, exp_file)

println("=========================================================\n")
