abstract type AbstractBridge end

"""
    bridge_constrained_variables(BT::Type{<:AbstractBridge}, model::MOI.ModelLike,
                                set::MOI.AbstractVectorSet)
"""
function bridge_constrained_variables end

function MOI.get(::MOI.ModelLike, attr::MOI.AbstractConstraintAttribute,
                 bridge::AbstractBridge)
    throw(ArgumentError("Variable bridge of type `$(typeof(bridge))` does not support accessing the attribute `$attr`."))
end

"""
    MOI.get(b::AbstractBridge, ::MOI.NumberOfConstraints{F, S}) where {F, S}

The number of constraints of the type `F`-in-`S` created by the bridge `b` in the model.
"""
MOI.get(b::AbstractBridge, ::MOI.NumberOfConstraints) = 0

"""
    MOI.supports_constrained_variables(::Type{<:AbstractBridge},
                                       ::Type{<:MOI.AbstractVectorSet})::Bool

Return a `Bool` indicating whether the bridges of type `BT` support bridging
constrained variables in `S`.
"""
function MOI.supports_constrained_variables(::Type{<:AbstractBridge},
                                            ::Type{<:MOI.AbstractVectorSet})
    return false
end
