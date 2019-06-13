abstract type AbstractBridge <: MOIB.AbstractBridge end

struct IndexInVector
    value::Int
end

function bridge_constrained_variable end

"""
    bridge_constrained_variables(BT::Type{<:AbstractBridge}, model::MOI.ModelLike,
                                set::MOI.AbstractVectorSet)
"""
function bridge_constrained_variables end

function MOI.get(::MOI.ModelLike, attr::MOI.AbstractConstraintAttribute,
                 bridge::AbstractBridge)
    throw(ArgumentError("Variable bridge of type `$(typeof(bridge))` does not support accessing the attribute `$attr`."))
end

function MOI.get(::MOI.ModelLike, attr::MOI.AbstractVariableAttribute,
                 bridge::AbstractBridge, ::IndexInVector)
    throw(ArgumentError("Variable bridge of type `$(typeof(bridge))` does not support accessing the attribute `$attr`."))
end

"""
    MOI.get(b::AbstractBridge, ::MOI.NumberOfConstraints{F, S}) where {F, S}

The number of constraints of the type `F`-in-`S` created by the bridge `b` in the model.
"""
MOI.get(b::AbstractBridge, ::MOI.NumberOfConstraints) = 0

function MOI.get(::AbstractBridge,
                 ::MOI.ListOfConstraintIndices{F, S}) where {F, S}
    return MOI.ConstraintIndex{F, S}[]
end

"""
    supports_constrained_variables(::Type{<:AbstractBridge},
                                   ::Type{<:MOI.AbstractSet})::Bool

Return a `Bool` indicating whether the bridges of type `BT` support bridging
constrained variables in `S`.
"""
function supports_constrained_variables(::Type{<:AbstractBridge},
                                        ::Type{<:MOI.AbstractSet})
    return false
end

"""
    added_constrained_variable_types(BT::Type{<:AbstractBridge},
                                     S::Type{<:MOI.AbstractSet})

Return a list of the types of constraints that bridges of type `BT` add for
bridging constrained variabled in `S`.
"""
function MOIB.added_constrained_variable_types(BT::Type{<:AbstractBridge},
                                     S::Type{<:MOI.AbstractSet})
    MOIB.added_constrained_variable_types(concrete_bridge_type(BT, S))
end

"""
    added_constraint_types(BT::Type{<:AbstractBridge},
                                     S::Type{<:MOI.AbstractSet})

Return a list of the types of constrained variables that bridges of type `BT` add
for bridging constrained variabled in `S`.
"""
function MOIB.added_constraint_types(BT::Type{<:AbstractBridge},
                                     S::Type{<:MOI.AbstractSet})
    MOIB.added_constraint_types(concrete_bridge_type(BT, S))
end

function concrete_bridge_type(bridge_type::DataType,
                              ::Type{<:MOI.AbstractSet})
    return bridge_type
end

function concrete_bridge_type(b::MOIB.AbstractBridgeOptimizer,
                              S::Type{<:MOI.AbstractSet})
    return concrete_bridge_type(MOIB.bridge_type(b, S), S)
end
