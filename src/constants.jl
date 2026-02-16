# Leopold & Maddock (1953) / Allen et al. (1994) Coefficients
# Depth = A * Q^B
const DEPTH_A = 0.34
const DEPTH_B = 0.341

# Velocity = A * Q^B
const VEL_A   = 0.19
const VEL_B   = 0.266

# Earth Radius for Haversine (meters)
const EARTH_RADIUS = 6371003.0

# GloWPa D8 Flow Direction Bitmask
# Mapping: Value => (Lat_Offset, Lon_Offset)
const D8_MAP = Dict(
    1   => (0, 1),   # E
    2   => (1, 1),   # SE
    4   => (1, 0),   # S
    8   => (1, -1),  # SW
    16  => (0, -1),  # W
    32  => (-1, -1), # NW
    64  => (-1, 0),  # N
    128 => (-1, 1)   # NE
)