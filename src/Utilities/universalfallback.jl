"""
    UniversalFallback

The `UniversalFallback` can be applied on a `ModelLike` `model` to create the
model `UniversalFallback(model)` supporting *any* constaints and attributes.
This allows to have a specialized implementation in `model` for performance
critical constraints and attributes while still supporting other attributes
with a small performance penalty. Note that `model` is unaware of constraints
and attributes stored by `UniversalFallback` so this is not appropriate if
`model` is an optimizer (for this reason, `optimize!` has not been
implemented). In that case, optimizer bridges should be used instead.
"""
mutable struct UniversalFallback{MT} <: MOI.ModelLike
    model::MT
    constraints::Dict{Tuple{DataType, DataType}, Dict} # See https://github.com/JuliaOpt/JuMP.jl/issues/1152
    nextconstraintid::Int64
    con_to_name::Dict{CI, String}
    name_to_con::Union{Dict{String, MOI.ConstraintIndex}, Nothing}
    optattr::Dict{MOI.AbstractOptimizerAttribute, Any}
    modattr::Dict{MOI.AbstractModelAttribute, Any}
    varattr::Dict{MOI.AbstractVariableAttribute, Dict{VI, Any}}
    conattr::Dict{MOI.AbstractConstraintAttribute, Dict{CI, Any}}
    function UniversalFallback{MT}(model::MOI.ModelLike) where {MT}
        new{typeof(model)}(model,
                           Dict{Tuple{DataType, DataType}, Dict}(),
                           0,
                           Dict{CI, String}(),
                           nothing,
                           Dict{MOI.AbstractOptimizerAttribute, Any}(),
                           Dict{MOI.AbstractModelAttribute, Any}(),
                           Dict{MOI.AbstractVariableAttribute, Dict{VI, Any}}(),
                           Dict{MOI.AbstractConstraintAttribute, Dict{CI, Any}}())
    end
end
UniversalFallback(model::MOI.ModelLike) = UniversalFallback{typeof(model)}(model)

function MOI.is_empty(uf::UniversalFallback)
    return MOI.is_empty(uf.model) && isempty(uf.constraints) &&
        isempty(uf.modattr) && isempty(uf.varattr) && isempty(uf.conattr)
end
function MOI.empty!(uf::UniversalFallback)
    MOI.empty!(uf.model)
    empty!(uf.constraints)
    uf.nextconstraintid = 0
    empty!(uf.con_to_name)
    uf.name_to_con = nothing
    empty!(uf.modattr)
    empty!(uf.varattr)
    empty!(uf.conattr)
end
function MOI.copy_to(uf::UniversalFallback, src::MOI.ModelLike; kws...)
    MOIU.automatic_copy_to(uf, src; kws...)
end
function supports_default_copy_to(uf::UniversalFallback, copy_names::Bool)
    return supports_default_copy_to(uf.model, copy_names)
end

# References
MOI.is_valid(uf::UniversalFallback, idx::VI) = MOI.is_valid(uf.model, idx)
function MOI.is_valid(uf::UniversalFallback, idx::CI{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.is_valid(uf.model, idx)
    else
        haskey(uf.constraints, (F, S)) && haskey(uf.constraints[(F, S)], idx)
    end
end
function MOI.delete(uf::UniversalFallback, ci::CI{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.delete(uf.model, ci)
    else
        if !MOI.is_valid(uf, ci)
            throw(MOI.InvalidIndex(ci))
        end
        delete!(uf.constraints[(F, S)], ci)
        if haskey(uf.con_to_name, ci)
            delete!(uf.con_to_name, ci)
        end
        uf.name_to_con = nothing
    end
    for d in values(uf.conattr)
        delete!(d, ci)
    end
end
function MOI.delete(uf::UniversalFallback, vi::VI)
    MOI.delete(uf.model, vi)
    for d in values(uf.varattr)
        delete!(d, vi)
    end
    for (FS, constraints) in uf.constraints
        for (ci, constraint) in constraints
            f, s = constraint
            if f isa MOI.SingleVariable
                if f.variable == vi
                    delete!(constraints, ci)
                end
            else
                constraints[ci] = removevariable(f, s, vi)
            end
        end
    end
end

# Attributes
_get(uf, attr::MOI.AbstractOptimizerAttribute)          = uf.optattr[attr]
_get(uf, attr::MOI.AbstractModelAttribute)              = uf.modattr[attr]
function _get(uf, attr::MOI.AbstractVariableAttribute, vi::VI)
    attribute_dict = get(uf.varattr, attr, nothing)
    if attribute_dict === nothing
        # It means the attribute is not set to any variable so in particular, it
        # is not set for `vi`
        return nothing
    end
    return get(attribute_dict, vi, nothing)
end
function _get(uf, attr::MOI.AbstractConstraintAttribute, ci::CI)
    attribute_dict = get(uf.conattr, attr, nothing)
    if attribute_dict === nothing
        # It means the attribute is not set to any constraint so in particular,
        # it is not set for `ci`
        return nothing
    end
    return get(attribute_dict, ci, nothing)
end
function MOI.get(uf::UniversalFallback,
                 attr::Union{MOI.AbstractOptimizerAttribute,
                             MOI.AbstractModelAttribute})
    if !MOI.is_copyable(attr) || MOI.supports(uf.model, attr)
        MOI.get(uf.model, attr)
    else
        _get(uf, attr)
    end
end
function MOI.get(uf::UniversalFallback,
                 attr::Union{MOI.AbstractVariableAttribute,
                             MOI.AbstractConstraintAttribute}, idx::MOI.Index)
    if MOI.supports(uf.model, attr, typeof(idx))
        MOI.get(uf.model, attr, idx)
    else
        _get(uf, attr, idx)
    end
end
function MOI.get(uf::UniversalFallback,
                 attr::MOI.NumberOfConstraints{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        return MOI.get(uf.model, attr)
    else
        return length(get(uf.constraints, (F, S), Dict{CI{F, S}, Tuple{F, S}}()))
    end
end
function MOI.get(uf::UniversalFallback,
                 listattr::MOI.ListOfConstraintIndices{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.get(uf.model, listattr)
    else
        collect(keys(get(uf.constraints, (F, S), Dict{CI{F, S}, Tuple{F, S}}())))
    end
end
function MOI.get(uf::UniversalFallback, listattr::MOI.ListOfConstraints)
    list = MOI.get(uf.model, listattr)
    for (FS, constraints) in uf.constraints
        if !isempty(constraints)
            push!(list, FS)
        end
    end
    list
end
function MOI.get(uf::UniversalFallback, listattr::MOI.ListOfOptimizerAttributesSet)
    list = MOI.get(uf.model, listattr)
    for attr in keys(uf.optattr)
        push!(list, attr)
    end
    list
end
function MOI.get(uf::UniversalFallback, listattr::MOI.ListOfModelAttributesSet)
    list = MOI.get(uf.model, listattr)
    for attr in keys(uf.modattr)
        push!(list, attr)
    end
    list
end
function MOI.get(uf::UniversalFallback, listattr::MOI.ListOfVariableAttributesSet)
    list = MOI.get(uf.model, listattr)
    for attr in keys(uf.varattr)
        push!(list, attr)
    end
    list
end
function MOI.get(uf::UniversalFallback, listattr::MOI.ListOfConstraintAttributesSet{F, S}) where {F, S}
    list = MOI.get(uf.model, listattr)
    for attr in keys(uf.conattr)
        push!(list, attr)
    end
    return list
end

# Name
# The names of constraints not supported by `uf.model` need to be handled
function MOI.set(uf::UniversalFallback, attr::MOI.ConstraintName, ci::CI{F, S}, name::String) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.set(uf.model, attr, ci, name)
    else
        uf.con_to_name[ci] = name
        uf.name_to_con = nothing # Invalidate the name map.
    end
    return
end
function MOI.get(uf::UniversalFallback, attr::MOI.ConstraintName, ci::CI{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        return MOI.get(uf.model, attr, ci)
    else
        return get(uf.con_to_name, ci, EMPTYSTRING)
    end
end

MOI.get(uf::UniversalFallback, ::Type{VI}, name::String) = MOI.get(uf.model, VI, name)
function MOI.get(uf::UniversalFallback, ::Type{CI{F, S}}, name::String) where {F, S}
    if uf.name_to_con === nothing
        uf.name_to_con = build_name_to_con_map(uf.con_to_name)
    end

    if MOI.supports_constraint(uf.model, F, S)
        ci = MOI.get(uf.model, CI{F, S}, name)
        if ci !== nothing && haskey(uf.name_to_con, name)
            error("Multiple constraints have the name $name.")
        end
        return ci
    else
        ci = get(uf.name_to_con, name, nothing)
        if ci == CI{Nothing, Nothing}(0)
            error("Multiple constraints have the name $name.")
        elseif ci isa CI{F, S}
            return ci
        else
            return nothing
        end
    end
end
function MOI.get(uf::UniversalFallback, ::Type{CI}, name::String)
    if uf.name_to_con === nothing
        uf.name_to_con = build_name_to_con_map(uf.con_to_name)
    end

    ci = MOI.get(uf.model, CI, name)
    if ci === nothing
        uf_ci = get(uf.name_to_con, name, nothing)
        if uf_ci == CI{Nothing, Nothing}(0)
            error("Multiple constraints have the name $name.")
        else
            return uf_ci
        end
    else
        if haskey(uf.name_to_con, name)
            error("Multiple constraints have the name $name.")
        end
        return ci
    end
end

_set(uf, attr::MOI.AbstractOptimizerAttribute, value) = uf.optattr[attr] = value
_set(uf, attr::MOI.AbstractModelAttribute, value)     = uf.modattr[attr] = value
function _set(uf, attr::MOI.AbstractVariableAttribute, vi::VI, value)
    if !haskey(uf.varattr, attr)
        uf.varattr[attr] = Dict{VI, Any}()
    end
    uf.varattr[attr][vi] = value
end
function _set(uf, attr::MOI.AbstractConstraintAttribute, ci::CI, value)
    if !haskey(uf.conattr, attr)
        uf.conattr[attr] = Dict{CI, Any}()
    end
    uf.conattr[attr][ci] = value
end
MOI.supports(::UniversalFallback, ::Union{MOI.AbstractModelAttribute, MOI.AbstractOptimizerAttribute}) = true
function MOI.set(uf::UniversalFallback, attr::Union{MOI.AbstractOptimizerAttribute, MOI.AbstractModelAttribute}, value)
    if MOI.supports(uf.model, attr)
        return MOI.set(uf.model, attr, value)
    else
        return _set(uf, attr, value)
    end
end
MOI.supports(::UniversalFallback, ::Union{MOI.AbstractVariableAttribute, MOI.AbstractConstraintAttribute}, ::Type{<:MOI.Index}) = true
function MOI.set(uf::UniversalFallback, attr::MOI.AbstractVariableAttribute, idx::VI, value)
    if MOI.supports(uf.model, attr, typeof(idx))
        return MOI.set(uf.model, attr, idx, value)
    else
        return _set(uf, attr, idx, value)
    end
end
function MOI.set(uf::UniversalFallback, attr::MOI.AbstractConstraintAttribute, idx::CI{F, S}, value) where {F, S}
    if MOI.supports_constraint(uf.model, F, S) && MOI.supports(uf.model, attr, CI{F, S})
        return MOI.set(uf.model, attr, idx, value)
    else
        return _set(uf, attr, idx, value)
    end
end

# Constraints
MOI.supports_constraint(uf::UniversalFallback, ::Type{F}, ::Type{S}) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet} = true
function _new_constraint_index(uf, f::MOI.SingleVariable, s::MOI.AbstractScalarSet)
    return CI{MOI.SingleVariable, typeof(s)}(f.variable.value)
end
function _new_constraint_index(uf, f::MOI.AbstractFunction, s::MOI.AbstractSet)
    uf.nextconstraintid += 1
    return CI{typeof(f), typeof(s)}(uf.nextconstraintid)
end
function MOI.add_constraint(uf::UniversalFallback, f::MOI.AbstractFunction, s::MOI.AbstractSet)
    F = typeof(f)
    S = typeof(s)
    if MOI.supports_constraint(uf.model, F, S)
        return MOI.add_constraint(uf.model, f, s)
    else
        constraints = get!(uf.constraints, (F, S)) do
            Dict{CI{F, S}, Tuple{F, S}}()
        end::Dict{CI{F, S}, Tuple{F, S}}
        ci = _new_constraint_index(uf, f, s)
        constraints[ci] = (f, s)
        return ci
    end
end
function MOI.modify(uf::UniversalFallback, ci::CI{F, S}, change::MOI.AbstractFunctionModification) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.modify(uf.model, ci, change)
    else
        (f, s) = uf.constraints[(F, S)][ci]
        uf.constraints[(F, S)][ci] = (modifyfunction(f, change), s)
    end
end

function MOI.get(uf::UniversalFallback, attr::MOI.ConstraintFunction, ci::CI{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.get(uf.model, attr, ci)
    else
        MOI.throw_if_not_valid(uf, ci)
        uf.constraints[(F, S)][ci][1]
    end
end
function MOI.get(uf::UniversalFallback, attr::MOI.ConstraintSet, ci::CI{F, S}) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.get(uf.model, attr, ci)
    else
        MOI.throw_if_not_valid(uf, ci)
        uf.constraints[(F, S)][ci][2]
    end
end
function MOI.set(uf::UniversalFallback, ::MOI.ConstraintFunction, ci::CI{F,S}, func::F) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.set(uf.model, MOI.ConstraintFunction(), ci, func)
    else
        MOI.throw_if_not_valid(uf, ci)
        if F == MOI.SingleVariable
            throw(MOI.SettingSingleVariableFunctionNotAllowed())
        end
        (_, s) = uf.constraints[(F, S)][ci]
        uf.constraints[(F, S)][ci] = (func, s)
    end
end
function MOI.set(uf::UniversalFallback, ::MOI.ConstraintSet, ci::CI{F,S}, set::S) where {F, S}
    if MOI.supports_constraint(uf.model, F, S)
        MOI.set(uf.model, MOI.ConstraintSet(), ci, set)
    else
        MOI.throw_if_not_valid(uf, ci)
        (f, _) = uf.constraints[(F, S)][ci]
        uf.constraints[(F, S)][ci] = (f, set)
    end
end

# Objective
MOI.modify(uf::UniversalFallback, obj::MOI.ObjectiveFunction, change::MOI.AbstractFunctionModification) = MOI.modify(uf.model, obj, change)

# Variables
MOI.add_variable(uf::UniversalFallback) = MOI.add_variable(uf.model)
MOI.add_variables(uf::UniversalFallback, n) = MOI.add_variables(uf.model, n)
