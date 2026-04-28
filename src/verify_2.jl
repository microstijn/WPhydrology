using Rasters
using Dates
using DimensionalData

"""
    verify_output(generated_path::String, expected_path::String)
Returns (passed::Bool, errors::Vector{String})
"""
function verify_output(generated_path::String, expected_path::String)
    # ADD THIS TEMPORARY DEBUG LINE:
    #println("DEBUG: Checking if this exactly exists -> \"$generated_path\"")

    errors = String[]

    if !isfile(generated_path)
        push!(errors, "Generated file not found: $(basename(generated_path))")
        return false, errors
    end
    if !isfile(expected_path)
        push!(errors, "Expected file not found: $(basename(expected_path))")
        return false, errors
    end

    r_gen = Raster(generated_path)
    r_exp = Raster(expected_path)
    passed = true

    # 1. Dimensions
    if size(r_gen) != size(r_exp)
        push!(errors, "Dimension mismatch: Gen $(size(r_gen)) vs Exp $(size(r_exp))")
        passed = false
    end

    # 2. Spatial Extent & Resolution
    try
        x_gen, x_exp = lookup(r_gen, X), lookup(r_exp, X)
        y_gen, y_exp = lookup(r_gen, Y), lookup(r_exp, Y)

        if !(step(x_gen) ≈ step(x_exp))
            push!(errors, "X Res mismatch: Gen $(step(x_gen)) vs Exp $(step(x_exp))")
            passed = false
        end
        if !(step(y_gen) ≈ step(y_exp))
            push!(errors, "Y Res mismatch: Gen $(step(y_gen)) vs Exp $(step(y_exp))")
            passed = false
        end
        if !(first(x_gen) ≈ first(x_exp)) || !(last(x_gen) ≈ last(x_exp))
            push!(errors, "X Extent mismatch: Gen [$(first(x_gen)), $(last(x_gen))] vs Exp [$(first(x_exp)), $(last(x_exp))]")
            passed = false
        end
        if !(first(y_gen) ≈ first(y_exp)) || !(last(y_gen) ≈ last(y_exp))
            push!(errors, "Y Extent mismatch: Gen [$(first(y_gen)), $(last(y_gen))] vs Exp [$(first(y_exp)), $(last(y_exp))]")
            passed = false
        end
        if DimensionalData.order(x_gen) != DimensionalData.order(x_exp)
            push!(errors, "X Axis Order mismatch")
            passed = false
        end
        if DimensionalData.order(y_gen) != DimensionalData.order(y_exp)
            push!(errors, "Y Axis Order mismatch")
            passed = false
        end
    catch e
        push!(errors, "Spatial lookup error (missing axes): $e")
        passed = false
    end

    # 3. Missing Value Types
    mv_gen = missingval(r_gen)
    mv_exp = missingval(r_exp)
    if !isequal(mv_gen, mv_exp)
        push!(errors, "⚠️ Warning: Missing value mismatch: Gen `$mv_gen` vs Exp `$mv_exp`")
    end

    # 4. Values (Scale checks)
    vals_gen = filter(!isnan, collect(skipmissing(r_gen)))
    vals_exp = filter(!isnan, collect(skipmissing(r_exp)))

    if isempty(vals_gen) && !isempty(vals_exp)
        push!(errors, "Generated raster is empty but Expected has data.")
        passed = false
    elseif !isempty(vals_gen) && isempty(vals_exp)
        push!(errors, "Expected raster is empty but Generated has data.")
        passed = false
    elseif !isempty(vals_gen) && !isempty(vals_exp)
        min_g, max_g = extrema(vals_gen)
        min_e, max_e = extrema(vals_exp)

        # Flag if values are wildly off scale
        if min_g > max_e * 10 || max_g < min_e / 10
            push!(errors, "Scale mismatch. Gen: [$min_g, $max_g], Exp: [$min_e, $max_e]")
            passed = false
        end
    end

    return passed, errors
end


"""
    verify_scenario_month(scenario_dir, expected_dir, month_str)
Returns (all_passed::Bool, month_errors::Vector{String})
"""
function verify_scenario_month(scenario_dir::String, expected_dir::String, month_str::String)
    paths = [
        ("Runoff",      joinpath(scenario_dir, "runoff", "runoff_$(month_str).tif"),             joinpath(expected_dir, "runoff", "runoff_daymonmean_$(month_str).tif")),
        ("Discharge",   joinpath(scenario_dir, "discharge", "discharge_$(month_str).tif"),       joinpath(expected_dir, "discharge", "discharge_monmean_$(month_str).tif")),
        ("River Depth", joinpath(scenario_dir, "river_depth", "river_depth_$(month_str).tif"),   joinpath(expected_dir, "rdepth", "rdepth_monmean_$(month_str).tif")),
        ("Res Time",    joinpath(scenario_dir, "river_restime", "river_restime_$(month_str).tif"), joinpath(expected_dir, "river_restime", "river_restime_monmean_$(month_str).tif"))
    ]

    all_passed = true
    month_errors = String[]

    for (var_name, gen_path, exp_path) in paths
        passed, errs = verify_output(gen_path, exp_path)
        if !passed || !isempty(errs)
            all_passed = all_passed && passed # Keep track of overall failure
            for e in errs
                push!(month_errors, "   [$var_name] $e")
            end
        end
    end

    return all_passed, month_errors
end


"""
    run_batch_verifications(generated_base_dir, expected_dir)
"""
function run_batch_verifications(generated_base_dir::String, expected_dir::String)
    items = readdir(generated_base_dir, join=true)

    # SMART FILTER: Only keep directories that actually contain a "runoff" subfolder.
    # This automatically ignores "routing", "doc", "riverTemp", "logs", etc.
    scenario_dirs = filter(x -> isdir(x) && isdir(joinpath(x, "runoff")), items)

    if isempty(scenario_dirs)
        println("❌ No scenario folders found in $generated_base_dir")
        return
    end

    total_scenarios = length(scenario_dirs)
    
    # Dictionary to hold all errors: Dict("ScenarioName" => ["Error 1", "Error 2"])
    error_log = Dict{String, Vector{String}}()

    println("\n🚀 RUNNING SILENT BATCH VERIFICATION ($total_scenarios Scenarios)...\n")

    for scenario_dir in scenario_dirs
        scenario_name = basename(scenario_dir)
        print("Scanning $scenario_name ... ") # Print without newline

        scenario_passed = true
        scenario_errors = String[]

        for m in 1:12
            month_str = "m" * lpad(m, 2, "0")
            month_passed, m_errors = verify_scenario_month(scenario_dir, expected_dir, month_str)
            
            if !month_passed || !isempty(m_errors)
                scenario_passed = false
                push!(scenario_errors, "- Month $month_str:")
                append!(scenario_errors, m_errors)
            end
        end

        if scenario_passed
            println("✅ PASSED")
        else
            println("❌ FAILED")
            error_log[scenario_name] = scenario_errors
        end
    end

    # ==========================================
    # FINAL SUMMARY REPORT
    # ==========================================
    println("\n=========================================================")
    println("📊 BATCH VERIFICATION SUMMARY")
    println("=========================================================")
    if isempty(error_log)
        println("🎉 PERFECT RUN! All $(total_scenarios) scenarios passed perfectly.")
    else
        println("🛑 SOME FAILURES DETECTED.")
        println("   Passed: $(total_scenarios - length(error_log))")
        println("   Failed: $(length(error_log))")
        println("\n--- DETAILED ERROR LOG ---")
        
        for (scenario, errs) in error_log
            println("\n📁 $scenario:")
            for e in errs
                println(e)
            end
        end
    end
    println("=========================================================\n")
end

# ==========================================
# EXECUTION BLOCK
# ==========================================
gen_base_dir = raw"C:\Users\peete074\Documents\hydroOut"
exp_dir      = joinpath(@__DIR__, "..", "hydrology")

if length(ARGS) >= 2
    gen_base_dir = ARGS[1]
    exp_dir      = ARGS[2]
end

run_batch_verifications(gen_base_dir, exp_dir)