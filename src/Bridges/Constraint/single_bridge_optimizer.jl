"""
    SingleBridgeOptimizer{BT<:AbstractBridge, OT<:MOI.ModelLike} <: AbstractBridgeOptimizer

The `SingleBridgeOptimizer` bridges any constraint supported by the bridge `BT`.
This is in contrast with the [`MathOptInterface.Bridges.LazyBridgeOptimizer`](@ref)
which only bridges the constraints that are unsupported by the internal model,
even if they are supported by one of its bridges.
"""
mutable struct SingleBridgeOptimizer{BT<:AbstractBridge, OT<:MOI.ModelLike} <: MOIB.AbstractBridgeOptimizer
    model::OT
    map::Map # index of bridged constraint -> constraint bridge
    con_to_name::Dict{MOI.ConstraintIndex, String}
    name_to_con::Union{Dict{String, MOI.ConstraintIndex}, Nothing}
end
function SingleBridgeOptimizer{BT}(model::OT) where {BT, OT <: MOI.ModelLike}
    SingleBridgeOptimizer{BT, OT}(
        model, Map(), Dict{MOI.ConstraintIndex, String}(), nothing)
end

function bridges(bridge::MOI.Bridges.AbstractBridgeOptimizer)
    return EmptyMap()
end
function bridges(bridge::SingleBridgeOptimizer)
    return bridge.map
end

function MOIB.supports_bridging_constraint(
    b::SingleBridgeOptimizer{BT}, F::Type{<:MOI.AbstractFunction},
    S::Type{<:MOI.AbstractSet}) where BT
    return MOI.supports_constraint(BT, F, S)
end
function MOIB.is_bridged(b::SingleBridgeOptimizer, F::Type{<:MOI.AbstractFunction},
                    S::Type{<:MOI.AbstractSet})
    return MOIB.supports_bridging_constraint(b, F, S)
end
function MOIB.is_bridged(b::SingleBridgeOptimizer, S::Type{<:MOI.AbstractSet})
    return false
end
function MOIB.bridge_type(::SingleBridgeOptimizer{BT},
                          ::Type{<:MOI.AbstractFunction},
                          ::Type{<:MOI.AbstractSet}) where BT
    return BT
end
