"""
    RSOCtoPSDBridge{T} <: Bridges.Variable.AbstractBridge

Transforms constrained variables in [`MathOptInterface.RotatedSecondOrderCone`](@ref)
to constrained variables in [`MathOptInterface.PositiveSemidefiniteConeTriangle`](@ref).
"""
struct RSOCtoPSDBridge{T} <: AbstractBridge
    # `t` is `variables[1]`
    # `u` is `variables[2]/2`
    # `x` is `variables[3:end]`
    variables::Vector{MOI.VariableIndex}
    psd::MOI.ConstraintIndex{MOI.VectorOfVariables, MOI.PositiveSemidefiniteConeTriangle}
    off_diag::Vector{MOI.ConstraintIndex{MOI.SingleVariable, MOI.EqualTo{T}}}
    diag::Vector{MOI.ConstraintIndex{MOI.ScalarAffineFunction{T}, MOI.EqualTo{T}}}
end
function bridge_constrained_variables(::Type{RSOCtoPSDBridge{T}},
                                      model::MOI.ModelLike,
                                      set::MOI.RotatedSecondOrderCone) where T
    dim = set.dimension - 1
    variables, psd = MOI.add_constrained_variables(
        model, MOI.PositiveSemidefiniteConeTriangle(dim))
    # This is `2 * u`
    u2 = MOI.SingleVariable(variables[3])
    off_diag = MOI.ConstraintIndex{MOI.SingleVariable, MOI.EqualTo{T}}[]
    diag = MOI.ConstraintIndex{MOI.ScalarAffineFunction{T}, MOI.EqualTo{T}}[]
    k = 3
    for j in 3:dim
        k += 1
        for i in 2:(j-1)
            k += 1
            push!(off_diag,
                  MOI.add_constraint(model, MOI.SingleVariable(variables[k]),
                                     MOI.EqualTo(zero(T))))
        end
        k += 1
        func = MOIU.operate(-, T, u2, MOI.SingleVariable(variables[k]))
        push!(diag, MOI.add_constraint(model, func, MOI.EqualTo(zero(T))))
    end
    @assert k == trimap(dim, dim)
    return RSOCtoPSDBridge{T}(variables, psd, off_diag, diag)
end

function supports_constrained_variables(
    ::Type{<:RSOCtoPSDBridge}, ::Type{MOI.RotatedSecondOrderCone})
    return true
end
function MOIB.added_constrained_variable_types(::Type{<:RSOCtoPSDBridge})
    return [(MOI.PositiveSemidefiniteConeTriangle,)]
end
function MOIB.added_constraint_types(::Type{RSOCtoPSDBridge{T}}) where T
    return [(MOI.SingleVariable, MOI.EqualTo{T}), (MOI.ScalarAffineFunction{T}, MOI.EqualTo{T})]
end

# Attributes, Bridge acting as a model
function MOI.get(bridge::RSOCtoPSDBridge, ::MOI.NumberOfVariables)
    return length(bridge.variables)
end
function MOI.get(bridge::RSOCtoPSDBridge, ::MOI.ListOfVariableIndices)
    return bridge.variables
end
function MOI.get(bridge::RSOCtoPSDBridge{T},
                 ::MOI.NumberOfConstraints{MOI.SingleVariable,
                                           MOI.EqualTo{T}}) where T
    return length(bridge.off_diag)
end
function MOI.get(bridge::RSOCtoPSDBridge{T},
                 ::MOI.ListOfConstraintIndices{MOI.SingleVariable,
                                               MOI.EqualTo{T}}) where T
    return bridge.off_diag
end
function MOI.get(bridge::RSOCtoPSDBridge{T},
                 ::MOI.NumberOfConstraints{MOI.ScalarAffineFunction{T},
                                           MOI.EqualTo{T}}) where T
    return length(bridge.diag)
end
function MOI.get(bridge::RSOCtoPSDBridge{T},
                 ::MOI.ListOfConstraintIndices{MOI.ScalarAffineFunction{T},
                                               MOI.EqualTo{T}}) where T
    return bridge.diag
end

# Attributes, Bridge acting as a constraint

function trimap(i::Integer, j::Integer)
    if i < j
        trimap(j, i)
    else
        div((i-1)*i, 2) + j
    end
end
function _variable_map(i::IndexInVector)
    if i.value == 1
        return 1
    elseif i.value == 2
        return 3
    else
        return trimap(1, i.value - 1)
    end
end
function _variable(bridge::RSOCtoPSDBridge, i::IndexInVector)
    return bridge.variables[_variable_map(i)]
end

function MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintPrimal,
                 bridge::RSOCtoPSDBridge{T}) where T
    values = MOI.get(model, attr, bridge.psd)
    n = length(bridge.diag) + 3
    mapped = [values[_variable_map(IndexInVector(i))] for i in 1:n]
    mapped[2] /= 2
    return mapped
end
function MOI.get(model::MOI.ModelLike, attr::MOI.ConstraintDual,
                 bridge::RSOCtoPSDBridge{T}) where T
    dual = MOI.get(model, attr, bridge.psd)
    n = length(bridge.diag) + 3
    mapped = [dual[_variable_map(IndexInVector(i))] for i in 1:n]
    for ci in bridge.diag
        mapped[2] += MOI.get(model, attr, ci)
    end
    for i in 2:length(mapped)
        # For `i = 2`, we multiply by 2 because it is `2u`.
        # For `i > 2`, we multiply by 2 because to account for the difference
        # of scalar product `MOIU.set_dot`.
        mapped[i] *= 2
    end
    return mapped
end

function MOI.get(model::MOI.ModelLike, attr::MOI.VariablePrimal,
                 bridge::RSOCtoPSDBridge{T}, i::IndexInVector) where T
    value = MOI.get(model, attr, _variable(bridge, i))
    if i.value == 2
        return value / 2
    else
        return value
    end
end

function MOIB.bridged_function(bridge::RSOCtoPSDBridge{T}, i::IndexInVector) where T
    func = MOI.SingleVariable(_variable(bridge, i))
    if i.value == 2
        return MOIU.operate(/, T, func, convert(T, 2))
    else
        return convert(MOI.ScalarAffineFunction{T}, func)
    end
end
function unbridged_map(bridge::RSOCtoPSDBridge{T}, vi::MOI.VariableIndex,
                       i::IndexInVector) where T
    sv = MOI.SingleVariable(vi)
    if i.value == 2
        func = MOIU.operate(*, T, convert(T, 2), sv)
    else
        func = convert(MOI.ScalarAffineFunction{T}, sv)
    end
    return _variable(bridge, i) => func
end
