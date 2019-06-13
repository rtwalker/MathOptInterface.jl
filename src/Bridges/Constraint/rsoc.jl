"""
    RSOCBridge{T, F, G}

The `RotatedSecondOrderCone` is `SecondOrderCone` representable; see [1, p. 104].
Indeed, we have ``2tu = (t/√2 + u/√2)^2 - (t/√2 - u/√2)^2`` hence
```math
2tu \\ge || x ||_2^2
```
is equivalent to
```math
(t/√2 + u/√2)^2 \\ge || x ||_2^2 + (t/√2 - u/√2)^2.
```
We can therefore use the transformation ``(t, u, x) \\mapsto (t/√2+u/√2, t/√2-u/√2, x)``.
Note that the linear transformation is a symmetric involution (i.e. it is its own transpose and its own inverse).
That means in particular that the norm is of constraint primal and duals are preserved by the tranformation.

[1] Ben-Tal, Aharon, and Arkadi Nemirovski. *Lectures on modern convex optimization: analysis, algorithms, and engineering applications*. Society for Industrial and Applied Mathematics, 2001.
"""
struct RSOCBridge{T, F, G} <: AbstractBridge
    soc::CI{F, MOI.SecondOrderCone}
end
function rotate_function(f::MOI.AbstractVectorFunction, T::Type)
    d = MOI.output_dimension(f)
    f_scalars = MOIU.eachscalar(f)
    t = f_scalars[1]
    u = f_scalars[2]
    x = f_scalars[3:d]
    s2 = √2
    ts = MOIU.operate!(/, T, t, s2)
    us = MOIU.operate!(/, T, u, s2)
    # Cannot use `operate!` here since `ts` and `us` are needed for the next
    # line
    y  = ts - us
    z  = MOIU.operate!(+, T, ts, us)
    return MOIU.operate(vcat, T, z, y, x)
end
function bridge_constraint(::Type{RSOCBridge{T, F, G}}, model,
                           f::MOI.AbstractVectorFunction,
                           s::MOI.RotatedSecondOrderCone) where {T, F, G}
    soc = MOI.add_constraint(model, rotate_function(f, T),
                             MOI.SecondOrderCone(MOI.dimension(s)))
    return RSOCBridge{T, F, G}(soc)
end

function MOI.supports_constraint(::Type{RSOCBridge{T}},
                                ::Type{<:MOI.AbstractVectorFunction},
                                ::Type{MOI.RotatedSecondOrderCone}) where T
    return true
end
MOIB.added_constrained_variable_types(::Type{<:RSOCBridge}) = Tuple{DataType}[]
function MOIB.added_constraint_types(::Type{<:RSOCBridge{T, F}}) where {T, F}
    return [(F, MOI.SecondOrderCone)]
end
function concrete_bridge_type(::Type{<:RSOCBridge{T}},
                              G::Type{<:MOI.AbstractVectorFunction},
                              ::Type{MOI.RotatedSecondOrderCone}) where T
    S = MOIU.promote_operation(/, T, MOIU.scalar_type(G), T)
    Y = MOIU.promote_operation(-, T, S, S)
    Z = MOIU.promote_operation(+, T, S, S)
    F = MOIU.promote_operation(vcat, T, Z, Y, G)
    RSOCBridge{T, F, G}
end

# Attributes, Bridge acting as a model
function MOI.get(b::RSOCBridge{T, F},
                 ::MOI.NumberOfConstraints{F, MOI.SecondOrderCone}) where {T, F}
    return 1
end
function MOI.get(b::RSOCBridge{T, F},
                 ::MOI.ListOfConstraintIndices{F, MOI.SecondOrderCone}) where {T, F}
    return [b.soc]
end

# References
function MOI.delete(model::MOI.ModelLike, c::RSOCBridge)
    MOI.delete(model, c.soc)
end

# Attributes, Bridge acting as a constraint
function MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintFunction,
                 bridge::RSOCBridge{T, F, G}) where {T, F, G}
    # As it is an involution, we can just reapply the same transformation
    func = MOI.get(model, attr, bridge.soc)
    return MOIU.convert_approx(G, rotate_function(func, T))
end
function MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintSet, bridge::RSOCBridge)
    set = MOI.get(model, attr, bridge.soc)
    return MOI.RotatedSecondOrderCone(MOI.dimension(set))
end
# As the linear transformation is a symmetric involution,
# the constraint primal and dual both need to be processed by reapplying the same transformation
function _get(model, attr::Union{MOI.ConstraintPrimal, MOI.ConstraintDual}, c::RSOCBridge)
    x = MOI.get(model, attr, c.soc)
    s2 = √2
    [x[1]/s2+x[2]/s2; x[1]/s2-x[2]/s2; x[3:end]]
end
# Need to define both `get` methods and redirect to `_get` to avoid ambiguity in dispatch
MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintPrimal, c::RSOCBridge) = _get(model, attr, c)
MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintDual, c::RSOCBridge) = _get(model, attr, c)
