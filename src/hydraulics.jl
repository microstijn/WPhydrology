using Rasters, Distances, Dates

using DimensionalData.Dimensions.Lookups


"""
    format_for_glowpa(r::Raster)
Dynamically pads a cropped raster into a full global 720x360 raster,
shifts the coordinate lookups to Intervals(Start()), and ensures
missing values are strictly recorded as `missing`.
"""
function format_for_glowpa(r::Raster)
    # calculate the Y placement
    y_lookups = lookup(r, Y)
    res = abs(step(y_lookups)) # Should be 0.5
    
    # Since 'r' uses Center(), the true top edge is half a pixel north of the first center point
    top_edge = first(y_lookups) + (res / 2.0)
    
    # Global grid starts exactly at 90.0°N. Calculate how many rows down we need to start.
    row_start = round(Int, (90.0 - top_edge) / res) + 1
    row_end   = row_start + size(r, Y) - 1

    # Create a blank global matrix filled with `missing`
    global_data = Matrix{Union{Float32, Missing}}(missing, 720, 360)

    # Clean the data
    clean_data = map(x -> isnothing(x) || isnan(x) ? missing : Float32(x), r)

    # Paste into the rows!
    global_data[:, row_start:row_end] .= clean_data

    # Define expected GloWPa coordinates
    x_dim = X(range(-180.0, step=0.5, length=720); sampling=Intervals(Start()))
    y_dim = Y(range(89.5, step=-0.5, length=360); sampling=Intervals(Start()))

    return Raster(global_data, (x_dim, y_dim); missingval=missing)
end

"""
    compute_glowpa_month(runoff_mm, baseflow_mm, discharge_m3s, flowdir, days)
Returns (Runoff_rate, Depth, Residence_Time).
"""
function compute_glowpa_month(r_m::Raster, bf_m::Raster, q_m::Raster, fd::Raster, days::Int)
    lats, lons = lookup(fd, Y), lookup(fd, X)
    n_lon, n_lat = length(lons), length(lats)
    haversine = Haversine(EARTH_RADIUS)
    
    # Runoff (Total mm -> mm/day)
    # Safely handle missing/negative no-data values to prevent negative leaks
    glowpa_runoff = map(r_m, bf_m) do r, b
        # If either value is technically missing, or if they are a negative NoData flag
        if ismissing(r) || ismissing(b) || r < 0.0 || b < 0.0
            # You can return 0.0f0, or 'missing' depending on what your write function expects.
            # Using missing is usually safer for final GeoTIFF writes.
            return missing 
        else
            return Float32((r + b) / days)
        end
    end
    
    depth = zeros(Float32, size(fd))
    restime = zeros(Float32, size(fd))
    
    for I in CartesianIndices(fd)
        # check for missing in flowdir or discharge
        val_fd = fd[I]
        val_q  = q_m[I]

        if ismissing(val_fd) || ismissing(val_q)
            continue
        end

        f_dir = Int(val_fd)
        q_val = val_q
        
        if q_val > 0
            # Depth
            depth[I] = DEPTH_A * q_val^DEPTH_B
            
            # Residence Time
            if haskey(D8_MAP, f_dir)
                off_lat, off_lon = D8_MAP[f_dir]
                next_lat = clamp(I[2] + off_lat, 1, n_lat)
                next_lon = mod1(I[1] + off_lon, n_lon)
                
                p1 = (lats[I[2]], lons[I[1]])
                p2 = (lats[next_lat], lons[next_lon])
                dist = colwise(haversine, [p1], [p2])[1]
                
                vel = VEL_A * q_val^VEL_B
                restime[I] = dist / (max(vel, 0.01) * 86400.0)
            end
        end
    end
    
    return glowpa_runoff, Raster(depth, dims(fd)), Raster(restime, dims(fd))
end