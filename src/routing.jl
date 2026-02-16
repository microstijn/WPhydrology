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
        if ismissing(val); continue; end # Skip missing
        
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
    
    # Only set 'acc' to 1.0 if the input 'fd' was not missing
    for I in 1:length(fd)
        if !ismissing(fd[I])
            acc[I] = 1.0f0
        end
    end
    
    while !isempty(queue)
        u = popfirst!(queue)
        v = downstream[u]
        # Only accumulate if v is a valid downstream neighbor
        if v != 0 && v != u && !ismissing(acc[v]) && !ismissing(acc[u])
            acc[v] += acc[u]
            in_degree[v] -= 1
            if in_degree[v] == 0; push!(queue, v); end
        end
    end
    
    return Raster(reshape(acc, dims_size), dims(fd))
end