"""
    AbstractBridgeOptimizer

A bridge optimizer applies given constraint bridges to a given optimizer thus
extending the types of supported constraints. The attributes of the inner
optimizer are automatically transformed to make the bridges transparent, e.g.
the variables and constraints created by the bridges are hidden.

By convention, the inner optimizer should be stored in a `model` field and
the dictionary mapping constraint indices to bridges should be stored in a
`bridges` field. If a bridge optimizer deviates from these conventions, it
should implement the functions `MOI.optimize!` and `bridge` respectively.
"""
abstract type AbstractBridgeOptimizer <: MOI.AbstractOptimizer end

# AbstractBridgeOptimizer interface

"""
    is_bridged(b::AbstractBridgeOptimizer, F::Type{<:MOI.AbstractFunction},
              S::Type{<:MOI.AbstractSet})::Bool

Return a `Bool` indicating whether `b` tries to bridge `F`-in-`S` constraints
instead of passing it as is to its internal model.
"""
function is_bridged end
# Syntactic sugar
function is_bridged(b::AbstractBridgeOptimizer, ::Type{CI{F, S}}) where {F, S}
    return is_bridged(b, F, S)
end
is_bridged(::AbstractBridgeOptimizer, vi::MOI.VariableIndex) = vi.value < 0

"""
    supports_bridging_constraint(b::AbstractBridgeOptimizer,
                               F::Type{<:MOI.AbstractFunction},
                               S::Type{<:MOI.AbstractSet})::Bool

Return a `Bool` indicating whether `b` supports bridging `F`-in-`S` constraints.
"""
function supports_bridging_constraint(::AbstractBridgeOptimizer,
                                      ::Type{<:MOI.AbstractFunction},
                                      ::Type{<:MOI.AbstractSet})
    return false
end

#function supports_bridging_constrained_variables(
#    ::AbstractBridgeOptimizer, ::Type{<:MOI.AbstractVectorSet})
#    return false
#end


"""
    bridge_type(b::AbstractBridgeOptimizer,
                F::Type{<:MOI.AbstractFunction},
                S::Type{<:MOI.AbstractSet})

Return the `AbstractBridge` type to be used to bridge `F`-in-`S` constraints.
This function should only be called if `is_bridged(b, F, S)`.
"""
function bridge_type end

# If `ci.value < 0` is the constraint of a bridged constrained variable,
# but if `S` is `SingleVariable`, it can also simply be a constraint on a
# bridged variable.
function is_variable_bridged(b::AbstractBridgeOptimizer,
                             ci::MOI.ConstraintIndex)
    return ci.value < 0
end
function is_variable_bridged(b::AbstractBridgeOptimizer,
                             ci::MOI.ConstraintIndex{MOI.SingleVariable})
    return ci.value < 0 && !haskey(Constraint.bridges(b), ci)
end

"""
    bridge(b::AbstractBridgeOptimizer, ci::CI)

Return the `AbstractBridge` used to bridge the constraint with index `ci`.
"""
function bridge(b::AbstractBridgeOptimizer, ci::CI{S}) where S
    if is_variable_bridged(b, ci)
        return bridge(b, MOI.VariableIndex(ci.value))
    else
        return Constraint.bridges(b)[ci]
    end
end
function bridge(b::AbstractBridgeOptimizer, vi::MOI.VariableIndex)
    return Variable.bridges(b)[vi]
end

# Implementation of the MOI interface for AbstractBridgeOptimizer

MOI.optimize!(b::AbstractBridgeOptimizer) = MOI.optimize!(b.model)
# By convention, the model should be stored in a `model` field

function MOI.is_empty(b::AbstractBridgeOptimizer)
    return isempty(Variable.bridges(b)) && isempty(Constraint.bridges(b)) &&
           MOI.is_empty(b.model)
end
function MOI.empty!(b::AbstractBridgeOptimizer)
    MOI.empty!(b.model)
    empty!(Variable.bridges(b))
    if !isempty(Constraint.bridges(b))
        empty!(Constraint.bridges(b))
        empty!(b.con_to_name)
        b.name_to_con = nothing
    end
end
function MOI.supports(b::AbstractBridgeOptimizer,
                      attr::Union{MOI.AbstractModelAttribute,
                                  MOI.AbstractOptimizerAttribute})
    return MOI.supports(b.model, attr)
end

function MOI.copy_to(mock::AbstractBridgeOptimizer, src::MOI.ModelLike; kws...)
    MOIU.automatic_copy_to(mock, src; kws...)
end
function MOIU.supports_default_copy_to(b::AbstractBridgeOptimizer,
                                       copy_names::Bool)
    return MOIU.supports_default_copy_to(b.model, copy_names)
end

# References
function _constraint_index(b::AbstractBridgeOptimizer, i::Integer)
    F, S = b.constraint_types[i]
    return MOI.ConstraintIndex{F, S}(i)
end
function MOI.is_valid(b::AbstractBridgeOptimizer, vi::MOI.VariableIndex)
    if is_bridged(b, vi)
        return haskey(Variable.bridges(b), vi)
    else
        return MOI.is_valid(b.model, vi)
    end
end
function MOI.is_valid(b::AbstractBridgeOptimizer, ci::MOI.ConstraintIndex{F, S}) where {F, S}
    if is_bridged(b, typeof(ci))
        if is_variable_bridged(b, ci)
            vi = MOI.VariableIndex(ci.value)
            return MOI.is_valid(b, vi) &&
                Variable.constrained_set(Variable.bridges(b), vi) == S
        else
            return haskey(Constraint.bridges(b), ci)
        end
    else
        return MOI.is_valid(b.model, ci)
    end
end
function MOI.delete(b::AbstractBridgeOptimizer, vi::MOI.VariableIndex)
    # Delete all `MOI.SingleVariable` constraint of this variable
    for ci in Constraint.variable_constraints(Constraint.bridges(b), vi)
        MOI.delete(b, ci)
    end
    if is_bridged(b, vi)
        if !MOI.is_valid(b, vi)
            throw(MOI.InvalidIndex(vi))
        end
        i = Variable.index_in_vector_of_variables(Variable.bridges(b), vi)
        if !iszero(i.value)
            message = string("Cannot delete a variable part of a bridged",
                             " vector of constrained variables.")
            throw(MOI.DeleteNotAllowed(vi, message))
        end
        MOI.delete(b, bridge(b, vi))
        delete!(Variable.bridges(b), vi)
    else
        MOI.delete(b.model, vi)
    end
end
function MOI.delete(b::AbstractBridgeOptimizer, ci::CI)
    if is_bridged(b, typeof(ci))
        if !MOI.is_valid(b, ci)
            throw(MOI.InvalidIndex(ci))
        end
        MOI.delete(b, bridge(b, ci))
        delete!(Constraint.bridges(b), ci)
        b.name_to_con = nothing
        if haskey(b.con_to_name, ci)
            delete!(b.con_to_name, ci)
        end
    else
        MOI.delete(b.model, ci)
    end
end

# Attributes
# List of indices of all constraints, including those bridged
function get_all_including_bridged(
    b::AbstractBridgeOptimizer,
    attr::MOI.ListOfVariableIndices)
    list = MOI.get(b.model, attr)
    if !isempty(Variable.bridges(b))
        list = append!(copy(list), keys(Variable.bridges(b)))
    end
    return list
end
function get_all_including_bridged(
    b::AbstractBridgeOptimizer,
    attr::MOI.ListOfConstraintIndices{F, S}) where {F, S}
    if is_bridged(b, F, S)
        return collect(Constraint.keys_of_type(Constraint.bridges(b),
                                               MOI.ConstraintIndex{F, S}))
    else
        return MOI.get(b.model, attr)
    end
end
# Remove constraints bridged by `bridge` from `list`
function _remove_bridged(list, bridge, attr)
    for c in MOI.get(bridge, attr)
        i = something(findfirst(isequal(c), list), 0)
        if !iszero(i)
            MOI.deleteat!(list, i)
        end
    end
end
function MOI.get(b::AbstractBridgeOptimizer,
                 attr::Union{MOI.ListOfConstraintIndices,
                             MOI.ListOfVariableIndices})
    list = get_all_including_bridged(b, attr)
    for bridge in values(Variable.bridges(b))
        _remove_bridged(list, bridge, attr)
    end
    for bridge in values(Constraint.bridges(b))
        _remove_bridged(list, bridge, attr)
    end
    return list
end
function MOI.get(b::AbstractBridgeOptimizer, attr::MOI.NumberOfVariables)
    s = MOI.get(b.model, attr) + length(Variable.bridges(b))
    for bridge in values(Variable.bridges(b))
        s -= MOI.get(bridge, attr)
    end
    for bridge in values(Constraint.bridges(b))
        s -= MOI.get(bridge, attr)
    end
    return s
end

# Number of all constraints, including those bridged
function get_all_including_bridged(
    b::AbstractBridgeOptimizer,
    attr::MOI.NumberOfConstraints{F, S}) where {F, S}
    num = if is_bridged(b, F, S)
        Constraint.number_of_type(Constraint.bridges(b), MOI.ConstraintIndex{F, S})
    else
        MOI.get(b.model, attr)
    end
    if F == MOI.VectorOfVariables || F == MOI.SingleVariable
        num += Variable.number_with_set(Variable.bridges(b), S)
    end
    return num
end
function MOI.get(b::AbstractBridgeOptimizer,
                 attr::MOI.NumberOfConstraints{F, S}) where {F, S}
    s = get_all_including_bridged(b, attr)
    # The constraints counted in `s` may have been added by bridges
    for bridge in values(Variable.bridges(b))
        s -= MOI.get(bridge, attr)
    end
    for bridge in values(Constraint.bridges(b))
        s -= MOI.get(bridge, attr)
    end
    return s
end
function MOI.get(b::AbstractBridgeOptimizer, attr::MOI.ListOfConstraints)
    list_of_types = copy(MOI.get(b.model, attr))
    append!(list_of_types, Constraint.list_of_key_types(Constraint.bridges(b)))
    # Some constraint types show up in `list_of_types` including when all the
    # constraints of that type have been created by bridges and not by the user.
    # The code in `NumberOfConstraints` takes care of removing these constraints
    # from the counter so we can rely on it to remove these constraint types.
    types_to_remove = findall(iszero.(
        map(FS -> MOI.get(b, MOI.NumberOfConstraints{FS...}()), list_of_types)))
    deleteat!(list_of_types, types_to_remove)
    return list_of_types
end

# Model an optimizer attributes
function MOI.get(b::AbstractBridgeOptimizer,
                 attr::Union{MOI.AbstractModelAttribute,
                             MOI.AbstractOptimizerAttribute})
    return unbridged_function(b, MOI.get(b.model, attr))
end
function MOI.set(b::AbstractBridgeOptimizer,
                  attr::Union{MOI.AbstractModelAttribute,
                              MOI.AbstractOptimizerAttribute},
                  value)
    return MOI.set(b.model, attr, bridged_function(b, value))
end

function _index(b::AbstractBridgeOptimizer, vi::MOI.VariableIndex)
    i = Variable.index_in_vector_of_variables(Variable.bridges(b), vi)
    if iszero(i.value)
        return tuple()
    else
        return (i,)
    end
end

# Variable attributes
function MOI.get(b::AbstractBridgeOptimizer,
                 attr::MOI.AbstractVariableAttribute,
                 index::MOI.VariableIndex)
    if is_bridged(b, index)
        return MOI.get(b, attr, bridge(b, index), _index(b, index)...)
    else
        return MOI.get(b.model, attr, index)
    end
end
function MOI.get(b::AbstractBridgeOptimizer,
                 attr::MOI.AbstractVariableAttribute,
                 indices::Vector{MOI.VariableIndex})
    if any(index -> is_bridged(b, index), indices)
        return MOI.get.(b, attr, indices)
    else
        return MOI.get(b.model, attr, indices)
    end
end
function MOI.supports(b::AbstractBridgeOptimizer,
                      attr::MOI.AbstractVariableAttribute,
                      IndexType::Type{<:MOI.Index})
    return MOI.supports(b.model, attr, IndexType)
end
function MOI.set(b::AbstractBridgeOptimizer,
                 attr::MOI.AbstractVariableAttribute,
                 index::MOI.Index, value)
    if is_bridged(b, index)
        return MOI.set(b, attr, bridge(b, index), value, _index(b, index)...)
    else
        return MOI.set(b.model, attr, index, value)
    end
end
function MOI.set(b::AbstractBridgeOptimizer,
                 attr::MOI.AbstractVariableAttribute,
                 indices::Vector{<:MOI.Index}, values::Vector)
    if any(index -> is_bridged(b, index), indices)
        return MOI.set.(b, attr, indices, values)
    else
        return MOI.set(b.model, attr, indices, values)
    end
end

# Constraint attributes
function MOI.get(b::AbstractBridgeOptimizer,
                 attr::MOI.AbstractConstraintAttribute, ci::CI)
    if is_bridged(b, typeof(ci))
        MOI.throw_if_not_valid(b, ci)
        br = bridge(b, ci)
        if attr isa MOI.ConstraintFunction && br isa Variable.AbstractBridge
            return Variable.function_for(Variable.bridges(b), ci)
        end
        if needs_fallback(b, attr, br)
            func = MOIU.get_fallback(b, attr, ci)
        else
            func = MOI.get(b, attr, br)
        end
    else
        func = MOI.get(b.model, attr, ci)
    end
    return unbridged_function(b, func)
end
function MOI.supports(b::AbstractBridgeOptimizer,
                      attr::MOI.AbstractConstraintAttribute,
                      IndexType::Type{CI{F, S}}) where {F, S}
    if is_bridged(b, IndexType)
        return MOI.supports(b, attr, Constraint.concrete_bridge_type(b, F, S))
    else
        return MOI.supports(b.model, attr, IndexType)
    end
end

function MOI.set(b::AbstractBridgeOptimizer,
                 attr::MOI.AbstractConstraintAttribute,
                 index::CI, value)
    if is_bridged(b, typeof(index))
        MOI.throw_if_not_valid(b, index)
        return MOI.set(b, attr, bridge(b, index), value)
    else
        return MOI.set(b.model, attr, index, value)
    end
end
## Getting and Setting names
function MOI.get(b::AbstractBridgeOptimizer, attr::MOI.ConstraintName,
                 constraint_index::CI)
    if is_bridged(b, typeof(constraint_index))
        return get(b.con_to_name, constraint_index, MOIU.EMPTYSTRING)
    else
        return MOI.get(b.model, attr, constraint_index)
    end
end

function MOI.supports(b::AbstractBridgeOptimizer, attr::MOI.ConstraintName,
                      Index::Type{CI{F,S}}) where {F,S}
    if is_bridged(b, Index)
        return true
    else
        return MOI.supports(b.model, attr, Index)
    end
end
function MOI.set(b::AbstractBridgeOptimizer, attr::MOI.ConstraintName,
                  constraint_index::CI, name::String)
    if is_bridged(b, typeof(constraint_index))
        b.con_to_name[constraint_index] = name
        b.name_to_con = nothing # Invalidate the name map.
    else
        MOI.set(b.model, attr, constraint_index, name)
    end
end

# Name (similar to `UniversalFallback`)
function MOI.get(b::AbstractBridgeOptimizer, IdxT::Type{MOI.VariableIndex},
                 name::String)
    return MOI.get(b.model, IdxT, name)
end

function MOI.get(b::AbstractBridgeOptimizer, IdxT::Type{<:MOI.ConstraintIndex},
                 name::String)
    if b.name_to_con === nothing
        b.name_to_con = MOIU.build_name_to_con_map(b.con_to_name)
    end

    if is_bridged(b, IdxT)
        ci = get(b.name_to_con, name, nothing)
        if ci == CI{Nothing, Nothing}(-1)
            error("Multiple constraints have the name $name.")
        elseif ci isa IdxT
            if MOI.get(b.model, CI, name) !== nothing
                error("Multiple constraints have the name $name.")
            end
            return ci
        else
            return nothing
        end
    else
        ci = MOI.get(b.model, IdxT, name)
        if ci !== nothing && haskey(b.name_to_con, name)
            error("Multiple constraints have the name $name.")
        end
        return ci
    end
end

# We have no information as to whether the constraint is in the bridge or the
# model. Therefore, we try the model first, and then the bridge if that fails.
function MOI.get(b::AbstractBridgeOptimizer, IdxT::Type{CI},
                 name::String)
    if b.name_to_con === nothing
        b.name_to_con = MOIU.build_name_to_con_map(b.con_to_name)
    end

    ci = MOI.get(b.model, IdxT, name)
    if ci === nothing
        b_ci = get(b.name_to_con, name, nothing)
        if b_ci == CI{Nothing, Nothing}(-1)
            error("Multiple constraints have the name $name.")
        else
            return b_ci
        end
    else
        if haskey(b.name_to_con, name)
            error("Multiple constraints have the name $name.")
        end

        return ci
    end
end

# Constraints
function MOI.supports_constraint(b::AbstractBridgeOptimizer,
                                 F::Type{<:MOI.AbstractFunction},
                                 S::Type{<:MOI.AbstractSet})
    if is_bridged(b, F, S)
        return supports_bridging_constraint(b, F, S)
    else
        return MOI.supports_constraint(b.model, F, S)
    end
end
function MOI.add_constraint(b::AbstractBridgeOptimizer, f::MOI.AbstractFunction,
                            s::MOI.AbstractSet)
    if Variable.has_bridges(Variable.bridges(b))
        if f isa MOI.SingleVariable
            if is_bridged(b, f.variable)
                if MOI.is_valid(b, MOI.ConstraintIndex{MOI.SingleVariable, typeof(s)}(f.variable.value))
                    # The other constraint could have been through a variable bridge.
                    error("Cannot add two `SingleVariable`-in-`$(typeof(s))`",
                          " on the same variable $(f.variable).")
                end
                BridgeType = Constraint.concrete_bridge_type(
                    Constraint.ScalarFunctionizeBridge{Float64}, typeof(f), typeof(s))
                bridge = Constraint.bridge_constraint(BridgeType, b, f, s)
                return Constraint.add_key_for_bridge(Constraint.bridges(b), bridge, f, s)
            end
        elseif f isa MOI.VectorOfVariables
            if any(vi -> is_bridged(b, vi), f.variables)
                BridgeType = Constraint.concrete_bridge_type(
                    Constraint.VectorFunctionizeBridge{Float64}, typeof(f), typeof(s))
                bridge = Constraint.bridge_constraint(BridgeType, b, f, s)
                return Constraint.add_key_for_bridge(Constraint.bridges(b), bridge, f, s)
            end
        else
            f = bridged_function(b, f)::typeof(f)
            f, s = MOIU.normalize_constant(f, s)
        end
    end
    if is_bridged(b, typeof(f), typeof(s))
        # We compute `BridgeType` first as `concrete_bridge_type` calls
        # `bridge_type` which might throw an `UnsupportedConstraint` error in
        # which case, we do not want any modification to have been done
        BridgeType = Constraint.concrete_bridge_type(b, typeof(f), typeof(s))
        # `add_constraint` might throw an `UnsupportedConstraint` but no
        # modification has been done in the previous line
        bridge = Constraint.bridge_constraint(BridgeType, b, f, s)
        return Constraint.add_key_for_bridge(Constraint.bridges(b), bridge, f, s)
    else
        return MOI.add_constraint(b.model, f, s)
    end
end
function MOI.add_constraints(b::AbstractBridgeOptimizer, f::Vector{F},
                             s::Vector{S}) where { F <: MOI.AbstractFunction,
                             S <: MOI.AbstractSet}
    if is_bridged(b, F, S)
        return MOI.add_constraint.(b, f, s)
    else
        if Variable.has_bridges(Variable.bridges(b))
            if S == MOI.SingleVariable
                if any(func -> is_bridged(b, func.variable), f)
                    return MOI.add_constraint.(b, f, s)
                end
            elseif S == MOI.VectorOfVariables
                if any(func -> any(vi -> is_bridged(b, vi), func.variables), f)
                    return MOI.add_constraint.(b, f, s)
                end
            else
                f = F[bridged_function(b, func)::F for func in f]
            end
        end
        return MOI.add_constraints(b.model, f, s)
    end
end
function is_bridged(::AbstractBridgeOptimizer,
                    ::Union{MOI.ScalarConstantChange, MOI.VectorConstantChange})
    return false
end
function is_bridged(b::AbstractBridgeOptimizer,
                    change::Union{MOI.ScalarCoefficientChange, MOI.MultirowChange})
    return is_bridged(b, change.variable)
end
function MOI.modify(b::AbstractBridgeOptimizer, ci::CI,
                    change::MOI.AbstractFunctionModification)
    if is_bridged(b, change)
        throw(MOI.ModifyConstraintNotAllowed(ci, change, "The variable is bridged."))
    end
    if is_bridged(b, typeof(ci))
        MOI.modify(b, bridge(b, ci), change)
    else
        MOI.modify(b.model, ci, change)
    end
end

# Objective
function MOI.modify(b::AbstractBridgeOptimizer, obj::MOI.ObjectiveFunction,
                     change::MOI.AbstractFunctionModification)
    MOI.modify(b.model, obj, change)
end

# Variables
MOI.add_variable(b::AbstractBridgeOptimizer) = MOI.add_variable(b.model)
MOI.add_variables(b::AbstractBridgeOptimizer, n) = MOI.add_variables(b.model, n)

#function MOI.supports_constrained_variables(b::AbstractBridgeOptimizer,
#                                            S::Type{<:MOI.AbstractVectorSet})
#    if is_bridged(b, S)
#        return supports_bridging_constrained_variables(b, S)
#    else
#        return MOI.supports_constrained_variables(b.model, S)
#    end
#end
function MOI.add_constrained_variables(b::AbstractBridgeOptimizer,
                                       set::MOI.AbstractVectorSet)
    if is_bridged(b, typeof(set))
        BridgeType = Variable.concrete_bridge_type(b, typeof(set))
        bridge = Variable.bridge_constrained_variables(BridgeType, b, set)
        return Variable.add_keys_for_bridge(Variable.bridges(b), bridge, set)
    else
        if is_bridged(b, MOI.VectorOfVariables, typeof(set))
            variables = MOI.add_variables(b, MOI.dimension(set))
            constraint = MOI.add_constraint(b, MOI.VectorOfVariables(variables), set)
            return variables, constraint
        else
            return MOI.add_constrained_variables(b.model, set)
        end
    end
end
function MOI.add_constrained_variable(b::AbstractBridgeOptimizer,
                                      set::MOI.AbstractScalarSet)
    if is_bridged(b, typeof(set))
        BridgeType = Variable.concrete_bridge_type(b, typeof(set))
        bridge = Variable.bridge_constrained_variable(BridgeType, b, set)
        return Variable.add_key_for_bridge(Variable.bridges(b), bridge, set)
    else
        if is_bridged(b, MOI.SingleVariable, typeof(set))
            variable = MOI.add_variable(b)
            constraint = MOI.add_constraint(b, MOI.SingleVariable(variable), set)
            return variable, constraint
        else
            return MOI.add_constrained_variable(b.model, set)
        end
    end
end


function variable_bridged_function(b::AbstractBridgeOptimizer,
                                   vi::MOI.VariableIndex)
    if is_bridged(b, vi)
        func = bridged_function(bridge(b, vi), _index(b, vi)...)
        # If two variable bridges are chained, `func` may still contain
        # bridged variables.
        return bridged_function(b, func)
    else
        return MOI.SingleVariable(vi)
    end
end

# Returns the function where every bridged variable is replaced by the bridged
# function. The function returned should have the same type.
function bridged_function(bridge::AbstractBridgeOptimizer,
                          func::MOI.AbstractFunction)
    if !Variable.has_bridges(Variable.bridges(bridge))
        # Shortcut, this allows performance to be unaltered when no variable
        # bridges are used.
        return func
    end
    # We assume that the type of `func` is not altered. This restricts
    # variable bridges to only return `ScalarAffineFunction` but otherwise,
    # the peformance would be bad.
    return MOIU.substitute_variables(vi -> variable_bridged_function(bridge, vi),
                                     func)::typeof(func)
end
bridged_function(bridge::AbstractBridgeOptimizer, value) = value

function unbridged_function(bridge::AbstractBridgeOptimizer,
                            func::MOI.AbstractFunction)
    if !Variable.has_bridges(Variable.bridges(bridge))
        return func
    end
    return MOIU.substitute_variables(
        vi -> Variable.unbridged_function(Variable.bridges(bridge), vi),
        func)::typeof(func)
end
function unbridged_function(bridge::AbstractBridgeOptimizer,
                            func::Union{MOI.SingleVariable, MOI.VectorOfVariables})
    return func # bridged variables are not allowed in non-bridged constraints
end
unbridged_function(bridge::AbstractBridgeOptimizer, value) = value


# TODO add transform
