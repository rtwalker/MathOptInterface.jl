struct Map <: AbstractDict{MOI.VariableIndex, AbstractBridge}
    # Constraint Index of bridged constraint -> Bridge.
    # It is set to `nothing` when the constraint is deleted.
    bridges::Vector{Union{Nothing, AbstractBridge}}
    # Constraint Index of bridged constraint -> Constraint type.
    constraint_types::Vector{Tuple{DataType, DataType}}
    # For `SingleVariable` constraints: (variable, set type) -> bridge
    single_variable_constraints::Dict{Tuple{Int64, DataType}, AbstractBridge}
end
function Map()
    return Map(Union{Nothing, AbstractBridge}[],
               Tuple{DataType, DataType}[],
               Dict{Tuple{Int64, DataType}, AbstractBridge}())
end
function Base.isempty(map::Map)
    return all(bridge -> bridge === nothing, map.bridges) &&
        isempty(map.single_variable_constraints)
end
function Base.empty!(map::Map)
    empty!(map.bridges)
    empty!(map.constraint_types)
    empty!(map.single_variable_constraints)
    return map
end
function Base.haskey(map::Map, ci::MOI.ConstraintIndex{F, S}) where {F, S}
    return 1 ≤ ci.value ≤ length(map.bridges) &&
        map.bridges[ci.value] !== nothing &&
        (F, S) == map.constraint_types[ci.value]
end
function Base.getindex(map::Map,
                       ci::MOI.ConstraintIndex)
    return map.bridges[ci.value]
end
function Base.haskey(map::Map, ci::MOI.ConstraintIndex{MOI.SingleVariable, S}) where S
    return haskey(map.single_variable_constraints, (ci.value, S))
end
function Base.getindex(map::Map,
                       ci::MOI.ConstraintIndex{MOI.SingleVariable, S}) where S
    return map.single_variable_constraints[(ci.value, S)]
end
function Base.delete!(map::Map, ci::MOI.ConstraintIndex)
    map.bridges[ci.value] = nothing
    return map
end
function Base.delete!(map::Map, ci::MOI.ConstraintIndex{MOI.SingleVariable, S}) where S
    delete!(map.single_variable_constraints, (ci.value, S))
    return map
end
function number_of_type(map::Map, C::Type{MOI.ConstraintIndex{F, S}}) where {F, S}
    return count(i -> haskey(map, C(i)), eachindex(map.bridges))
end
function keys_of_type(map::Map, C::Type{MOI.ConstraintIndex{F, S}}) where {F, S}
    return MOI.Bridges.LazyFilter(
        ci -> haskey(map, ci),
        MOI.Bridges.LazyMap{C}(
            i -> C(i), eachindex(map.bridges)))
end
function number_of_type(map::Map, C::Type{MOI.ConstraintIndex{MOI.SingleVariable, S}}) where S
    return count(key -> key[2] == S, keys(map.single_variable_constraints))
end
function keys_of_type(map::Map, C::Type{MOI.ConstraintIndex{MOI.SingleVariable, S}}) where S
    return MOI.Bridges.LazyMap{C}(
        key -> C(key[1]),
        MOI.Bridges.LazyFilter(key -> key[2] == S, keys(map.single_variable_constraints))
    )
end
function list_of_key_types(map::Map)
    list = Set{Tuple{DataType, DataType}}()
    for i in eachindex(map.bridges)
        if map.bridges[i] !== nothing
            push!(list, map.constraint_types[i])
        end
    end
    for key in keys(map.single_variable_constraints)
        push!(list, (MOI.SingleVariable, key[2]))
    end
    return list
end
function Base.values(map::Map)
    return MOI.Bridges.LazyCat((
        MOI.Bridges.LazyFilter(bridge -> bridge !== nothing, map.bridges),
        values(map.single_variable_constraints)
    ))
end
function variable_constraints(map::Map, vi::MOI.VariableIndex)
    cis = MOI.ConstraintIndex{MOI.SingleVariable}[]
    for key in keys(map.single_variable_constraints)
        if key[1] == vi.value
            push!(cis, MOI.ConstraintIndex{MOI.SingleVariable, key[2]}(vi.value))
        end
    end
    return cis
end
function add_key_for_bridge(map::Map, bridge::AbstractBridge,
                            func::MOI.AbstractFunction, set::MOI.AbstractSet)
    push!(map.bridges, bridge)
    push!(map.constraint_types, (typeof(func), typeof(set)))
    return MOI.ConstraintIndex{typeof(func), typeof(set)}(length(map.bridges))
end
function add_key_for_bridge(map::Map, bridge::AbstractBridge,
                            func::MOI.SingleVariable, set::MOI.AbstractScalarSet)
    map.single_variable_constraints[(func.variable.value, typeof(set))] = bridge
    return MOI.ConstraintIndex{MOI.SingleVariable, typeof(set)}(func.variable.value)
end
function _iterate2(map::Map, elem_state=iterate(map.single_variable_constraints))
    if elem_state === nothing
        return nothing
    else
        i, S = elem_state[1].first
        bridge = elem_state[1].second
        ci = MOI.ConstraintIndex{MOI.SingleVariable, S}(i)
        return ci => bridge, (2, elem_state[2])
    end
end
function _iterate1(map::Map, state=1)
    while state ≤ length(map.bridges) && map.bridges[state] === nothing
        state += 1
    end
    if state > length(map.bridges)
        return _iterate2(map)
    else
        F, S = map.constraint_types[state]
        return MOI.ConstraintIndex{F, S}(state) => map.bridges[state], (1, state + 1)
    end
end
Base.iterate(map::Map) = _iterate1(map)
function Base.iterate(map::Map, state)
    if state[1] == 1
        return _iterate1(map, state[2])
    else
        return _iterate2(map, iterate(map.single_variable_constraints, state[2]))
    end
end

struct EmptyMap <: AbstractDict{MOI.VariableIndex, AbstractBridge} end
Base.isempty(::EmptyMap) = true
function Base.empty!(::EmptyMap) end
Base.keys(::EmptyMap) = MOIB.EmptyVector{MOI.VariableIndex}()
Base.values(::EmptyMap) = MOIB.EmptyVector{AbstractBridge}()
has_bridges(::EmptyMap) = false
number_with_set(::EmptyMap, ::Type{<:MOI.AbstractSet}) = 0

"""
    SingleBridgeOptimizer{BT<:AbstractBridge, OT<:MOI.ModelLike} <: AbstractBridgeOptimizer

The `SingleBridgeOptimizer` bridges any constraint supported by the bridge `BT`.
This is in contrast with the [`MathOptInterface.Bridges.LazyBridgeOptimizer`](@ref)
which only bridges the constraints that are unsupported by the internal model,
even if they are supported by one of its bridges.
"""
mutable struct SingleBridgeOptimizer{BT<:AbstractBridge, OT<:MOI.ModelLike} <: MOIB.AbstractBridgeOptimizer
    model::OT
    map::Map
    con_to_name::Dict{CI, String}
    name_to_con::Union{Dict{String, MOI.ConstraintIndex}, Nothing}
end
function SingleBridgeOptimizer{BT}(model::OT) where {BT, OT <: MOI.ModelLike}
    SingleBridgeOptimizer{BT, OT}(model, Map(), Dict{CI, String}(), nothing)
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
