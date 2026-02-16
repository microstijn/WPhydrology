using Rasters, Distances, Dates

"""
    compute_glowpa_month(runoff_mm, baseflow_mm, discharge_m3s, flowdir, days)
Returns (Runoff_rate, Depth, Residence_Time).
"""
function compute_glowpa_month(r_m::Raster, bf_m::Raster, q_m::Raster, fd::Raster, days::Int)
    lats, lons = lookup(fd, Y), lookup(fd, X)
    n_lon, n_lat = length(lons), length(lats)
    haversine = Haversine(EARTH_RADIUS)
    
    # Runoff (Total mm -> mm/day)
    glowpa_runoff = (r_m .+ bf_m) ./ days
    
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