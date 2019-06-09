struct Map <: AbstractDict{MOI.VariableIndex, AbstractBridge}
    # Bridged constrained variables
    # `i` -> `0`: `VariableIndex(-i)` was added with `add_constrained_variable`.
    # `i` -> `j`: `VariableIndex(-i)` is was the `j`th  variable of
    #             `add_constrained_variables`.
    index_in_vector_of_variables::Vector{Int}
    # `i` -> `bridge`: `VariableIndex(-i)` was bridged by `bridge`.
    bridges::Vector{Union{Nothing, AbstractBridge}}
    sets::Vector{Union{Nothing, DataType}}
end
Map() = Map(Int[], Union{Nothing, AbstractBridge}[], Union{Nothing, DataType}[])
Base.isempty(map::Map) = all(bridge -> bridge === nothing, map.bridges)
function Base.empty!(map::Map)
    empty!(map.index_in_vector_of_variables)
    empty!(map.bridges)
    empty!(map.sets)
    return map
end
function bridge_index(map::Map, vi::MOI.VariableIndex)
    return -vi.value - map.index_in_vector_of_variables[-vi.value] + 1
end
function Base.haskey(map::Map, vi::MOI.VariableIndex)
    return -length(map.bridges) ≤ vi.value ≤ -1 &&
        map.bridges[bridge_index(map, vi)] !== nothing
end
function Base.getindex(map::Map, vi::MOI.VariableIndex)
    return map.bridges[bridge_index(map, vi)]
end
function Base.delete!(map::Map, vi::MOI.VariableIndex)
    map.bridges[bridge_index(vi)] = nothing
    map.sets[bridge_index(vi)] = nothing
    return map
end
function Base.keys(map::Map)
    return MOI.Bridges.LazyFilter(
        vi -> haskey(map, vi),
        MOI.Bridges.LazyMap{MOI.VariableIndex}(
            i -> MOI.VariableIndex(-i),
            eachindex(map.bridges)))
end
Base.length(map::Map) = count(bridge -> bridge !== nothing, map.bridges)
function Base.values(map::Map)
    return MOI.Bridges.LazyFilter(bridge -> bridge !== nothing, map.bridges)
end
function number_with_set(map::Map, S::Type{<:MOI.AbstractSet})
    return count(isequal(S), map.sets)
end
function index_in_vector_of_variables(map::Map, vi::MOI.VariableIndex)
    return IndexInVector(map.index_in_vector_of_variables[-vi.value])
end
has_bridges(map::Map) = !isempty(map.index_in_vector_of_variables)
function add_keys_for_bridge(map::Map, bridge::AbstractBridge,
                             set::MOI.AbstractVectorSet)
    if iszero(MOI.dimension(set))
        return MOI.VariableIndex[], MOI.ConstraintIndex{MOI.VectorOfVariables, typeof(set)}(0)
    else
        variables = MOI.VariableIndex[MOI.VariableIndex(-(length(map.bridges) + i))
                                      for i in 1:MOI.dimension(set)]
        push!(map.index_in_vector_of_variables, 1)
        push!(map.bridges, bridge)
        push!(map.sets, typeof(set))
        for i in 2:MOI.dimension(set)
            push!(map.index_in_vector_of_variables, i)
            push!(map.bridges, nothing)
            push!(map.sets, nothing)
        end
        index = first(variables).value
        return variables, MOI.ConstraintIndex{MOI.VectorOfVariables, typeof(set)}(index)
    end
end
function Base.iterate(map::Map, state=1)
    while state ≤ length(map.bridges) && map.bridges[state] === nothing
        state += 1
    end
    if state > length(map.bridges)
        return nothing
    else
        return MOI.VariableIndex(-state) => map.bridges[state], state + 1
    end
end

struct EmptyMap <: AbstractDict{MOI.VariableIndex, AbstractBridge} end
Base.isempty(::EmptyMap) = true
function Base.empty!(::EmptyMap) end
Base.length(::EmptyMap) = 0
Base.keys(::EmptyMap) = MOIB.EmptyVector{MOI.VariableIndex}()
Base.values(::EmptyMap) = MOIB.EmptyVector{AbstractBridge}()
has_bridges(::EmptyMap) = false
number_with_set(::EmptyMap, ::Type{<:MOI.AbstractSet}) = 0

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
end
function SingleBridgeOptimizer{BT}(model::OT) where {BT, OT <: MOI.ModelLike}
    SingleBridgeOptimizer{BT, OT}(model, Map())
end

function bridges(bridge::MOI.Bridges.AbstractBridgeOptimizer)
    return EmptyMap()
end
bridges(bridge::SingleBridgeOptimizer) = bridge.map

function MOIB.supports_bridging_constrained_variables(
    b::SingleBridgeOptimizer{BT}, S::Type{<:MOI.AbstractVectorSet}) where BT
    return MOI.supports_constrained_variables(BT, S)
end
function MOIB.is_bridged(::SingleBridgeOptimizer,
                         ::Type{<:MOI.AbstractFunction},
                         ::Type{<:MOI.AbstractSet})
    return false
end
function MOIB.is_bridged(b::SingleBridgeOptimizer, S::Type{<:MOI.AbstractVectorSet})
    return MOIB.supports_bridging_constrained_variables(b, S)
end
