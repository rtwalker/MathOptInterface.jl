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
config_with_basis = MOIT.TestConfig(basis = true)

@testset "Scalar functionize" begin
    MOI.empty!(mock)
    bridged_mock = MOIB.Constraint.ScalarFunctionize{Float64}(mock)
    x = MOI.add_variable(bridged_mock)
    y = MOI.add_variable(bridged_mock)
    sx = MOI.SingleVariable(x)
    sy = MOI.SingleVariable(y)
    ci = MOI.add_constraint(bridged_mock, sx, MOI.GreaterThan(0.0))
    @test MOI.get(bridged_mock, MOI.ConstraintFunction(), ci) ≈ sx
    MOI.set(bridged_mock, MOI.ConstraintFunction(), ci, sy)
    @test MOI.get(bridged_mock, MOI.ConstraintFunction(), ci) ≈ sy
    @test MOI.get(bridged_mock, MOI.ConstraintSet(), ci) == MOI.GreaterThan(0.0)
    MOI.set(bridged_mock, MOI.ConstraintSet(), ci, MOI.GreaterThan(1.0))
    @test MOI.get(bridged_mock, MOI.ConstraintSet(), ci) == MOI.GreaterThan(1.0)
    test_delete_bridge(bridged_mock, ci, 2, ((MOI.ScalarAffineFunction{Float64}, MOI.Interval{Float64}, 0),))

    MOIT.basic_constraint_tests(bridged_mock, config,
                                include=[(F, S) for
                                F in [MOI.SingleVariable],
                                S in [MOI.GreaterThan{Float64},
                                    MOI.LessThan{Float64}]
                                    ])

    for T in [Int, Float64], S in [MOI.GreaterThan{T}, MOI.LessThan{T}]
        @test MOIB.added_constraint_types(MOIB.Constraint.ScalarFunctionizeBridge{T, S}) ==
            [(MOI.ScalarAffineFunction{T}, S)]
    end


    @testset "linear2" begin
        MOI.empty!(bridged_mock)
        MOIU.set_mock_optimize!(mock,
            (mock::MOIU.MockOptimizer) -> MOIU.mock_optimize!(mock, [1, 0],
                 (MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})    => [-1],
                 (MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64}) => [0, 1],
            con_basis =
                [(MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})    => [MOI.NONBASIC],
                 (MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64}) => [MOI.BASIC, MOI.NONBASIC]]))
        MOIT.linear2test(bridged_mock, config_with_basis)

        for (i, ci) in enumerate(MOI.get(
            bridged_mock,
            MOI.ListOfConstraintIndices{MOI.SingleVariable,
                                        MOI.GreaterThan{Float64}}()))
            test_delete_bridge(bridged_mock, ci, 2,
                               ((MOI.ScalarAffineFunction{Float64},
                                 MOI.GreaterThan{Float64}, 0),),
                               num_bridged = 3 - i)
        end
    end
end

@testset "Vector functionize" begin
    MOI.empty!(mock)
    bridged_mock = MOIB.Constraint.VectorFunctionize{Float64}(mock)
    x = MOI.add_variable(bridged_mock)
    y = MOI.add_variable(bridged_mock)
    z = MOI.add_variable(bridged_mock)
    v1 = MOI.VectorOfVariables([x,y,z])
    v2 = MOI.VectorOfVariables([x,y,y])
    ci = MOI.add_constraint(bridged_mock, v1, MOI.PowerCone(0.1))
    @test MOI.get(bridged_mock, MOI.ConstraintFunction(), ci) ≈ v1
    MOI.set(bridged_mock, MOI.ConstraintFunction(), ci, v2)
    @test MOI.get(bridged_mock, MOI.ConstraintFunction(), ci) ≈ v2
    @test MOI.get(bridged_mock, MOI.ConstraintSet(), ci) == MOI.PowerCone(0.1)
    MOI.set(bridged_mock, MOI.ConstraintSet(), ci, MOI.PowerCone(0.2))
    @test MOI.get(bridged_mock, MOI.ConstraintSet(), ci) == MOI.PowerCone(0.2)
    test_delete_bridge(bridged_mock, ci, 3, ((MOI.VectorAffineFunction{Float64}, MOI.Nonnegatives, 0),))

    MOIT.basic_constraint_tests(bridged_mock, config,
                                include=[(F, S) for
                                F in [MOI.VectorOfVariables],
                                S in [MOI.Nonnegatives,
                                    MOI.Nonpositives]
                                    ])

    for T in [Int, Float64], S in [MOI.Nonnegatives, MOI.Nonpositives]
        @test MOIB.added_constraint_types(MOIB.Constraint.VectorFunctionizeBridge{T, S}) ==
            [(MOI.VectorAffineFunction{T}, S)]
    end

    @testset "lin1v" begin
        mock.optimize! = (mock::MOIU.MockOptimizer) -> MOIU.mock_optimize!(
            mock, [1.0, 0.0, 2.0],
            (MOI.VectorAffineFunction{Float64}, MOI.Nonnegatives) => [[0, 2, 0]],
            (MOI.VectorAffineFunction{Float64}, MOI.Zeros)        => [[-3, -1]])
        MOIT.lin1vtest(bridged_mock, config)
        ci = first(MOI.get(
            bridged_mock,
            MOI.ListOfConstraintIndices{MOI.VectorOfVariables,
                                        MOI.Nonnegatives}()))
        test_delete_bridge(bridged_mock, ci, 3,
                           ((MOI.VectorAffineFunction{Float64},
                             MOI.Nonnegatives, 0),))
    end
end
