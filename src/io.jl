using CSV, DataFrames, Rasters, Dates

"""
    parse_climate_timeseries(filepath::String, master_grid::Raster)
"""
function parse_climate_timeseries(filepath::String, master_grid::Raster)
    println("   Reading full time series from $filepath ...")
    
    df = CSV.read(filepath, DataFrame)
    
    # Extract Points
    points = collect(zip(df.Longitude, df.Latitude))
    
    # Debug stuff: There were some NA values
    sample_col = df[:, 3]
    valid_samples = filter(x -> !ismissing(x) && !isnan(x), sample_col)
    
    if isempty(valid_samples)
        println("      ⚠️  WARNING: Column 3 contains ONLY NaNs or Missing values!")
    else
        println("   🔎 RAW FILE INSPECTION (Column 3):")
        println("      Min Value: $(minimum(valid_samples))")
        println("      Max Value: $(maximum(valid_samples))")
    end
    # end debug stuff
    
    date_cols = names(df)[3:end]
    results = []
    
    for col_name in date_cols
        # Parse "YYYY-MM"
        dt = Date(col_name, "yyyy-mm")
        
        # Get raw values
        raw_vals = df[:, col_name]
        
        # CLEAN THE DATA
        clean_vals = map(x -> ismissing(x) || isnan(x) || x < 0 ? 0.0f0 : Float32(x), raw_vals)
        
        # Rasterize 
        r = rasterize(
            points; 
            to = master_grid, 
            values = clean_vals,
            op = +, 
            missingval = -9999.0f0, 
            fill = 0.0f0 
        )
        
        push!(results, (date=dt, raster=r))
    end
    
    println("   -> Extracted $(length(results)) time steps.")
    return results
end