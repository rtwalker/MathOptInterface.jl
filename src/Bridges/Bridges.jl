module Bridges

using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities

const CI = MOI.ConstraintIndex

include("utilities.jl")
include("bridge_optimizer.jl")

# Constraint bridges
include("Constraint/Constraint.jl")
include("Variable/Variable.jl")

include("lazy_bridge_optimizer.jl")

"""
    full_bridge_optimizer(model::MOI.ModelLike, ::Type{T}) where T

Returns a `LazyBridgeOptimizer` bridging `model` for every bridge defined in
this package and for the coefficient type `T`.
"""
function full_bridge_optimizer(model::MOI.ModelLike, ::Type{T}) where T
    bridged_model = LazyBridgeOptimizer(model)
    add_bridge(bridged_model, Constraint.GreaterToLessBridge{T})
    add_bridge(bridged_model, Constraint.LessToGreaterBridge{T})
    add_bridge(bridged_model, Constraint.NonnegToNonposBridge{T})
    add_bridge(bridged_model, Constraint.NonposToNonnegBridge{T})
    add_bridge(bridged_model, Constraint.ScalarizeBridge{T})
    add_bridge(bridged_model, Constraint.VectorizeBridge{T})
    add_bridge(bridged_model, Constraint.ScalarSlackBridge{T})
    add_bridge(bridged_model, Constraint.VectorSlackBridge{T})
    add_bridge(bridged_model, Constraint.ScalarFunctionizeBridge{T})
    add_bridge(bridged_model, Constraint.VectorFunctionizeBridge{T})
    add_bridge(bridged_model, Constraint.SplitIntervalBridge{T})
    add_bridge(bridged_model, Constraint.QuadtoSOCBridge{T})
    add_bridge(bridged_model, Constraint.GeoMeanBridge{T})
    add_bridge(bridged_model, Constraint.SquareBridge{T})
    add_bridge(bridged_model, Constraint.LogDetBridge{T})
    add_bridge(bridged_model, Constraint.RootDetBridge{T})
    add_bridge(bridged_model, Constraint.RSOCBridge{T})
    add_bridge(bridged_model, Constraint.RSOCtoPSDBridge{T})
    add_bridge(bridged_model, Constraint.SOCtoPSDBridge{T})
    add_bridge(bridged_model, Constraint.IndicatorActiveOnFalseBridge{T})
    return bridged_model
end

end # module
