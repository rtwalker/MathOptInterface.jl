"""
    SingleBridgeOptimizer{BT<:AbstractBridge, OT<:MOI.ModelLike} <: AbstractBridgeOptimizer

The `SingleBridgeOptimizer` bridges any constrained variables supported by the
bridge `BT`. This is in contrast with the [`MathOptInterface.Bridges.LazyBridgeOptimizer`](@ref)
which only bridges the constrained variables that are unsupported by the internal model,
even if they are supported by one of its bridges.
"""
mutable struct SingleBridgeOptimizer{BT<:AbstractBridge, OT<:MOI.ModelLike} <: MOIB.AbstractBridgeOptimizer
    model::OT
    map::Map # index of bridged variable -> variable bridge
    var_to_name::Dict{MOI.VariableIndex, String}
    name_to_var::Union{Dict{String, MOI.VariableIndex}, Nothing}
end
function SingleBridgeOptimizer{BT}(model::OT) where {BT, OT <: MOI.ModelLike}
    SingleBridgeOptimizer{BT, OT}(
        model, Map(), Dict{MOI.VariableIndex, String}(), nothing)
end

function bridges(bridge::MOI.Bridges.AbstractBridgeOptimizer)
    return EmptyMap()
end
bridges(bridge::SingleBridgeOptimizer) = bridge.map

function MOIB.supports_bridging_constraint(
    b::SingleBridgeOptimizer{BT}, ::Type{MOI.SingleVariable},
    S::Type{<:MOI.AbstractScalarSet}) where BT
    return supports_constrained_variables(BT, S)
end
function MOIB.supports_bridging_constraint(
    b::SingleBridgeOptimizer{BT}, ::Type{MOI.VectorOfVariables},
    S::Type{<:MOI.AbstractVectorSet}) where BT
    return supports_constrained_variables(BT, S)
end
function MOIB.is_bridged(b::SingleBridgeOptimizer, S::Type{<:MOI.AbstractScalarSet})
    return MOIB.supports_bridging_constraint(b, MOI.SingleVariable, S)
end
function MOIB.is_bridged(b::SingleBridgeOptimizer, S::Type{<:MOI.AbstractVectorSet})
    return MOIB.supports_bridging_constraint(b, MOI.VectorOfVariables, S)
end
function MOIB.is_bridged(::SingleBridgeOptimizer,
                         ::Type{<:MOI.AbstractFunction},
                         ::Type{<:MOI.AbstractSet})
    return false
end
function MOIB.bridge_type(::SingleBridgeOptimizer{BT},
                          ::Type{<:MOI.AbstractSet}) where BT
    return BT
end
