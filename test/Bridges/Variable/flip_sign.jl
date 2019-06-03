using Test

using MathOptInterface
const MOI = MathOptInterface
const MOIT = MathOptInterface.Test
const MOIU = MathOptInterface.Utilities
const MOIB = MathOptInterface.Bridges

include("../utilities.jl")

include("../simple_model.jl")

mock = MOIU.MockOptimizer(SimpleModel{Float64}())
config = MOIT.TestConfig()

@testset "NonposToNonneg" begin
    bridged_mock = MOIB.Variable.NonposToNonneg{Float64}(mock)

    MOIU.set_mock_optimize!(mock,
        (mock::MOIU.MockOptimizer) -> MOIU.mock_optimize!(
            mock, MOI.INFEASIBLE, MOI.INFEASIBLE_POINT,
            MOI.INFEASIBILITY_CERTIFICATE)
    )
    MOIT.lin4test(bridged_mock, config)

    @test MOI.get(mock, MOI.NumberOfVariables()) == 1
    @test length(MOI.get(mock, MOI.ListOfVariableIndices())) == 1
    @test first(MOI.get(mock, MOI.ListOfVariableIndices())).value ≥ 0
    @test MOI.get(bridged_mock, MOI.NumberOfVariables()) == 1
    @test MOI.get(bridged_mock, MOI.ListOfVariableIndices()) == [MOI.VariableIndex(-1)]
end
