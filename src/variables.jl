# Variables

"""
    struct AddVariableNotAllowed <: NotAllowedError
        message::String # Human-friendly explanation why the attribute cannot be set
    end

An error indicating that variables cannot be added to the model.
"""
struct AddVariableNotAllowed <: NotAllowedError
    message::String # Human-friendly explanation why the attribute cannot be set
end
AddVariableNotAllowed() = AddVariableNotAllowed("")

operation_name(::AddVariableNotAllowed) = "Adding variables"

"""
    add_variables(model::ModelLike, n::Int)::Vector{VariableIndex}

Add `n` scalar variables to the model, returning a vector of variable indices.

A [`AddVariableNotAllowed`](@ref) error is thrown if adding variables cannot be
done in the current state of the model `model`.
"""
add_variables(model::ModelLike, n) = throw(AddVariableNotAllowed())

"""
    add_variable(model::ModelLike)::VariableIndex

Add a scalar variable to the model, returning a variable index.

A [`AddVariableNotAllowed`](@ref) error is thrown if adding variables cannot be
done in the current state of the model `model`.
"""
add_variable(model::ModelLike) = throw(AddVariableNotAllowed())

#function supports_constrained_variables(
#    model::ModelLike, S::Type{<:AbstractVectorSet})
#    return MOI.supports_constraint(model, MOI.VectorOfVariables, S)
#end
function add_constrained_variable(model::ModelLike, set::AbstractScalarSet)
    variable = add_variable(model)
    constraint = add_constraint(model, SingleVariable(variable), set)
    return variable, constraint
end
function add_constrained_variables(model::ModelLike, sets::AbstractVector{<:AbstractScalarSet})
    variables = Vector{VariableIndex}(undef, length(sets))
    constraints = Vector{ConstraintIndex{SingleVariable, eltype(sets)}}(undef, length(sets))
    for (i, set) in enumerate(sets)
        variables[i], constraints[i] = add_constrained_variable(model, set)
    end
    return variables, constraints
end
function add_constrained_variables(model::ModelLike, set::AbstractVectorSet)
    variables = add_variables(model, dimension(set))
    constraint = add_constraint(model, VectorOfVariables(variables), set)
    return variables, constraint
end
