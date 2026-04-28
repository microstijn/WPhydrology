using Rasters

"""
    compute_flow_accumulation(fd::Raster)
Calculates flow accumulation.
"""
function compute_flow_accumulation(fd::Raster)
    println("Building flow graph...")
    dims_size = size(fd)
    n_lon, n_lat = dims_size
    downstream = zeros(Int, length(fd))
    in_degree  = zeros(Int, length(fd))
    
    # Build graph
    for I in CartesianIndices(fd)
        val = fd[I]
        if ismissing(val) || val < 0; continue; end # Skip missing or NoData flags
        
        f_dir = Int(val)
        src_idx = LinearIndices(fd)[I]
        
        if haskey(D8_MAP, f_dir)
            off_lat, off_lon = D8_MAP[f_dir]
            next_lat = clamp(I[2] + off_lat, 1, n_lat)
            next_lon = mod1(I[1] + off_lon, n_lon)
            
            dst_idx = LinearIndices(fd)[next_lon, next_lat]
            downstream[src_idx] = dst_idx
            in_degree[dst_idx] += 1
        end
    end
    
    # Accumulate
    queue = findall(x -> x == 0, in_degree)
    
    # Initialize with missings, then set valid cells to 1.0
    acc = Array{Union{Float32, Missing}}(missing, length(fd))
    
    for I in 1:length(fd) # i prefer length although i know it's not the most efficient way to loop through a raster, but it is the most straightforward
        if !ismissing(fd[I]) && fd[I] >= 0
            acc[I] = 1.0f0
        end
    end
    
    while !isempty(queue)
        u = popfirst!(queue)
        v = downstream[u]
        
        # Only proceed if it flows to a valid, different cell
        if v != 0 && v != u
            # graph traversal steps
            in_degree[v] -= 1
            if in_degree[v] == 0
                push!(queue, v)
            end
            
            # if the data is valid do math, otherwise keep it missing
            if !ismissing(acc[v]) && !ismissing(acc[u])
                acc[v] += acc[u]
            end
        end
    end
    
    return Raster(reshape(acc, dims_size), dims(fd))
end