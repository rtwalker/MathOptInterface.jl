module Variable

using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities
const MOIB = MOI.Bridges

# Definition of a variable bridge
include("bridge.jl")

# Bridge optimizer bridging a specific variable bridge
include("single_bridge_optimizer.jl")

# Variable bridges
include("flip_sign.jl")
const NonposToNonneg{T, OT<:MOI.ModelLike} = SingleBridgeOptimizer{NonposToNonnegBridge{T}, OT}

function add_all_bridges(bridged_model, T::Type)
    MOIB.add_bridge(bridged_model, NonposToNonnegBridge{T})
    return
end

end
