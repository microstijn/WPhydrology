using WPhydrology
using Test
using Rasters
using Dates
using CSV
using DataFrames
using DimensionalData # Required for explicit Intervals/Center definitions

# --- HELPER: Create a robust grid for testing ---
function mock_grid(vals::Matrix, start_val=10.0, res=1.0)
    # We start at 10.0 to avoid 0.0 edge cases.
    # We explicitly define the sampling as 'Intervals(Center())'
    # This means a point at 10.0 falls inside the cell centered at 10.0
    x_range = range(start_val, step=res, length=size(vals, 1))
    y_range = range(start_val, step=res, length=size(vals, 2))
    
    x_dim = X(x_range; sampling=Intervals(Center()))
    y_dim = Y(y_range; sampling=Intervals(Center()))
    
    return Raster(vals, (x_dim, y_dim))
end

@testset "WPhydrology.jl Tests" begin

    @testset "1. Routing Logic (Small 3x3 Grid)" begin
        # 1 1 1 (East)
        # 4 4 4 (South)
        # 0 0 0 (Sinks)
        data = [1 1 1; 4 4 4; 0 0 0]
        fd = mock_grid(data) # Defaults to start=10.0, res=1.0
        
        acc = compute_flow_accumulation(fd)
        
        # Center (2,2) flows South to (2,3)
        @test acc[2,3] > acc[2,2]
        @test acc[1,1] == 1.0
        
        # Missing value test
        data_missing = [1 1 1; 1 missing 1; 1 1 1]
        fd_missing = replace(mock_grid(data_missing), 0=>missing)
        acc_missing = compute_flow_accumulation(fd_missing)
        @test ismissing(acc_missing[2,2]) 
    end

    @testset "2. Hydraulics Physics" begin
        # 2x1 Grid
        q_val, r_val, b_val, days = 100.0, 10.0, 5.0, 30
        
        q_m = mock_grid(fill(q_val, (2,1)))
        r_m = mock_grid(fill(r_val, (2,1)))
        b_m = mock_grid(fill(b_val, (2,1)))
        fd  = mock_grid(fill(1, (2,1))) 
        
        ro_out, dep_out, res_out = compute_glowpa_month(r_m, b_m, q_m, fd, days)
        
        @test ro_out[1] ≈ (r_val + b_val) / days atol=0.001
        @test dep_out[1] ≈ 0.34 * (q_val^0.341) atol=0.001
        @test res_out[1] > 0.0
    end

    @testset "3. File IO (Text Parsing)" begin
        filename = "test_climate.txt"
        
        # WE USE COORDINATE 10.0
        # This matches the 'mock_grid' default start_val exactly.
        # Since the grid is 'Intervals(Center())', 10.0 is the dead center of the first pixel.
        content = """
        Latitude,Longitude,2061-01,2061-02
        10.0,10.0,50.0,60.0
        """
        write(filename, content)
        
        # Master Grid (1x1 centered at 10.0)
        master = mock_grid(fill(0.0f0, (1,1)))
        
        try
            results = parse_climate_timeseries(filename, master)
            
            @test length(results) == 2
            @test results[1].date == Date(2061, 1, 1)
            
            # 0.0 (background) + 50.0 (data) = 50.0
            @test results[1].raster[1] ≈ 50.0f0 atol=0.1
            @test results[2].raster[1] ≈ 60.0f0 atol=0.1
            
        finally
            rm(filename, force=true)
        end
    end

end