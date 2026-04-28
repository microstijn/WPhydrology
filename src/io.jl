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
        
        # Clean the data
        clean_vals = map(x -> ismissing(x) || isnan(x) || x < 0 ? 0.0f0 : Float32(x), raw_vals)
        
        # Initialize a new raster for this time step, filled with 0.0f0
        r = map(x -> 0.0f0, master_grid) 
        
        # set points in raster
        for (lon, lat, val) in zip(df.Longitude, df.Latitude, clean_vals)
            try
                # Use Contains() to find the correct grid cell and add the value
                r[X(Contains(lon)), Y(Contains(lat))] += val
            catch e
                # If a coordinate in the CSV falls completely outside the master_grid,
                # Rasters.jl throws a SelectorError. ignore it.
                continue
            end
        end
        
        push!(results, (date=dt, raster=r))
    end
    
    println("   -> Extracted $(length(results)) time steps.")
    return results
end