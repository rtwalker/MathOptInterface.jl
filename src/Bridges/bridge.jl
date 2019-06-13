abstract type AbstractBridge end

function needs_fallback(::MOI.ModelLike, ::MOI.AbstractConstraintAttribute,
                        ::AbstractBridge)
    return false
end

"""
    added_constraint_types(BT::Type{<:Variable.AbstractBridge})::Bool

Return a list of the types of constrained variables that bridges of concrete
type `BT` add. This is used by the [`LazyBridgeOptimizer`](@ref).
"""
function added_constrained_variable_types end

"""
    added_constraint_types(BT::Type{<:Constraint.AbstractBridge})::Bool

Return a list of the types of constraints that bridges of concrete type `BT`
add. This is used by the [`LazyBridgeOptimizer`](@ref).
"""
function added_constraint_types end
