# Continuous linear problems

# Basic solver, query, resolve
function linear1test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # simple 2 variable, 1 constraint problem
    # min -x
    # st   x + y <= 1   (x + y - 1 ∈ Nonpositives)
    #       x, y >= 0   (x, y ∈ Nonnegatives)

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.EqualTo{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.EqualTo{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    #@test MOI.get(model, MOI.SupportsAddConstraintAfterSolve())
    #@test MOI.get(model, MOI.SupportsAddVariableAfterSolve())
    #@test MOI.get(model, MOI.SupportsDeleteConstraint())

    MOI.empty!(model)
    @test MOI.is_empty(model)

    # We don't use `add_constrained_variable` for `v1` as we will modify the
    # `set` hence it will modify the bridged function if it is bridged by
    # `Variable.VectorizeBridge` which is not supported.
    v1 = MOI.add_variable(model)
    vc1 = MOI.add_constraint(model, MOI.SingleVariable(v1), MOI.GreaterThan(0.0))
    # We test this after the creation of every `SingleVariable` constraint
    # to ensure a good coverage of corner cases.
    @test vc1.value == v1.value
    # test fallback
    v2, vc2 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc2.value == v2.value
    @test MOI.get(model, MOI.NumberOfVariables()) == 2
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 2
    v = [v1, v2]

    cf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], v), 0.0)
    c = MOI.add_constraint(model, cf, MOI.LessThan(1.0))
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 1

    # note: adding some redundant zero coefficients to catch solvers that don't handle duplicate coefficients correctly:
    objf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([0.0,0.0,-1.0,0.0,0.0,0.0], [v; v; v]), 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    @test MOI.get(model, MOI.ObjectiveSense()) == MOI.MIN_SENSE

    if config.query
        vrs = MOI.get(model, MOI.ListOfVariableIndices())
        @test vrs == v || vrs == reverse(v)

        @test objf ≈ MOI.get(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())

        @test cf ≈ MOI.get(model, MOI.ConstraintFunction(), c)

        s = MOI.get(model, MOI.ConstraintSet(), c)
        @test s == MOI.LessThan(1.0)

        s = MOI.get(model, MOI.ConstraintSet(), vc1)
        @test s == MOI.GreaterThan(0.0)

        s = MOI.get(model, MOI.ConstraintSet(), vc2)
        @test s == MOI.GreaterThan(0.0)
    end

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ -1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [1, 0] atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 1 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ -1 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1 atol=atol rtol=rtol

            # reduced costs
            @test MOI.get(model, MOI.ConstraintDual(), vc1) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc2) ≈ 1 atol=atol rtol=rtol
        end
    end

    # change objective to Max +x

    objf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,0.0], v), 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.query
        @test objf ≈ MOI.get(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    end

    @test MOI.get(model, MOI.ObjectiveSense()) == MOI.MAX_SENSE

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [1, 0] atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 1 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1 atol=atol rtol=rtol

            @test MOI.get(model, MOI.ConstraintDual(), vc1) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc2) ≈ 1 atol=atol rtol=rtol
        end
    end

    # add new variable to get :
    # max x + 2z
    # s.t. x + y + z <= 1
    # x,y,z >= 0

    z = MOI.add_variable(model)
    push!(v, z)
    @test v[3] == z

    if config.query
        # Test that the modification of v has not affected the model
        vars = map(t -> t.variable_index, MOI.get(model, MOI.ConstraintFunction(), c).terms)
        @test vars == [v[1], v[2]] || vars == [v[2], v[1]]
        @test MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, v[1])], 0.0) ≈ MOI.get(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    end

    vc3 = MOI.add_constraint(model, MOI.SingleVariable(v[3]), MOI.GreaterThan(0.0))
    @test vc3.value == v[3].value
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 3

    if config.modify_lhs
        MOI.modify(model, c, MOI.ScalarCoefficientChange{Float64}(z, 1.0))
    else
        MOI.delete(model, c)
        cf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0,1.0], v), 0.0)
        c = MOI.add_constraint(model, cf, MOI.LessThan(1.0))
    end

    MOI.modify(model,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
        MOI.ScalarCoefficientChange{Float64}(z, 2.0)
    )

    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 1
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 3

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus(1)) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [0, 0, 1] atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 1 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 2 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -2 atol=atol rtol=rtol

            @test MOI.get(model, MOI.ConstraintDual(), vc1) ≈ 1 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc2) ≈ 2 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc3) ≈ 0 atol=atol rtol=rtol
        end
    end

    # setting lb of x to -1 to get :
    # max x + 2z
    # s.t. x + y + z <= 1
    # x >= -1
    # y,z >= 0
    MOI.set(model, MOI.ConstraintSet(), vc1, MOI.GreaterThan(-1.0))

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 3 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [-1, 0, 2] atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 3 atol=atol rtol=rtol
        end
    end

    # put lb of x back to 0 and fix z to zero to get :
    # max x + 2z
    # s.t. x + y + z <= 1
    # x, y >= 0, z = 0 (vc3)
    MOI.set(model, MOI.ConstraintSet(), vc1, MOI.GreaterThan(0.0))

    MOI.delete(model, vc3)

    vc3 = MOI.add_constraint(model, MOI.SingleVariable(v[3]), MOI.EqualTo(0.0))
    @test vc3.value == v[3].value
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 2

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [1, 0, 0] atol=atol rtol=rtol
    end

    # modify affine linear constraint set to be == 2 to get :
    # max x + 2z
    # s.t. x + y + z == 2 (c)
    # x,y >= 0, z = 0
    MOI.delete(model, c)
    # note: adding some redundant zero coefficients to catch solvers that don't handle duplicate coefficients correctly:
    cf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([0.0,0.0,0.0,1.0,1.0,1.0,0.0,0.0,0.0], [v; v; v]), 0.0)
    c = MOI.add_constraint(model, cf, MOI.EqualTo(2.0))
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 0
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.EqualTo{Float64}}()) == 1

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [2, 0, 0] atol=atol rtol=rtol
    end

    # modify objective function to x + 2y to get :
    # max x + 2y
    # s.t. x + y + z == 2 (c)
    # x,y >= 0, z = 0

    objf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,2.0,0.0], v), 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.query
        @test objf ≈ MOI.get(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    end

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 4 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [0, 2, 0] atol=atol rtol=rtol
    end

    # add constraint x - y >= 0 (c2) to get :
    # max x+2y
    # s.t. x + y + z == 2 (c)
    # x - y >= 0 (c2)
    # x,y >= 0 (vc1,vc2), z = 0 (vc3)

    cf2 = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, -1.0, 0.0], v), 0.0)
    c2 = MOI.add_constraint(model, cf2, MOI.GreaterThan(0.0))
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.EqualTo{Float64}}()) == 1
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.GreaterThan{Float64}}()) == 1
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 0
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.EqualTo{Float64}}()) == 1
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 2
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.LessThan{Float64}}()) == 0

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 3 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), v) ≈ [1, 1, 0] atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 2 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c2) ≈ 0 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), vc1) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), vc2) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), vc3) ≈ 0 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus(1)) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 3 atol=atol rtol=rtol

            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1.5 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c2) ≈ 0.5 atol=atol rtol=rtol

            @test MOI.get(model, MOI.ConstraintDual(), vc1) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc2) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc3) ≈ 1.5 atol=atol rtol=rtol
        end
    end

    if config.query
        @test MOI.get(model, MOI.ConstraintFunction(), c2) ≈ cf2
    end

    # delete variable x to get :
    # max 2y
    # s.t. y + z == 2
    # - y >= 0
    # y >= 0, z = 0

    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 2
    MOI.delete(model, v[1])
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 1

    if config.query
        err = MOI.InvalidIndex(vc1)
        # vc1 should have been deleted with `v[1]`.
        @test_throws err MOI.get(model, MOI.ConstraintFunction(), vc1)
        @test_throws err MOI.get(model, MOI.ConstraintSet(), vc1)

        @test MOI.get(model, MOI.ConstraintFunction(), c2) ≈ MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0, 0.0], [v[2], z]), 0.0)

        vrs = MOI.get(model, MOI.ListOfVariableIndices())
        @test vrs == [v[2], z] || vrs == [z, v[2]]
        @test MOI.get(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}()) ≈ MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0, 0.0], [v[2], z]), 0.0)
    end
end

# add_variable (one by one)
function linear2test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # Min -x
    # s.t. x + y <= 1
    # x, y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, vc1 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc1.value == x.value
    y, vc2 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc2.value == y.value
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 2

    @test MOI.get(model, MOI.NumberOfVariables()) == 2

    cf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], [x, y]), 0.0)
    c = MOI.add_constraint(model, cf, MOI.LessThan(1.0))
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 1

    objf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0,0.0], [x, y]), 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    @test MOI.get(model, MOI.ObjectiveSense()) == MOI.MIN_SENSE

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ -1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 1 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ -1 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1 atol=atol rtol=rtol

            # reduced costs
            @test MOI.get(model, MOI.ConstraintDual(), vc1) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc2) ≈ 1 atol=atol rtol=rtol
        end

        if config.basis
            @test MOI.get(model, MOI.ConstraintBasisStatus(), vc1) == MOI.BASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), vc2) == MOI.NONBASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC
        end
    end
end

# Issue #40 from Gurobi.jl
function linear3test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # min  x
    # s.t. x >= 0
    #      x >= 3

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.LessThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, vc = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc.value == x.value
    @test MOI.get(model, MOI.NumberOfVariables()) == 1

    cf = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0)
    c = MOI.add_constraint(model, cf, MOI.GreaterThan(3.0))

    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 1
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.GreaterThan{Float64}}()) == 1

    objf = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 3 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 3 atol=atol rtol=rtol

        if config.basis
            @test MOI.get(model, MOI.ConstraintBasisStatus(), vc) == MOI.BASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC
        end
    end

    # max  x
    # s.t. x <= 0
    #      x <= 3

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, vc = MOI.add_constrained_variable(model, MOI.LessThan(0.0))
    @test vc.value == x.value
    @test MOI.get(model, MOI.NumberOfVariables()) == 1

    cf = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0)
    c = MOI.add_constraint(model, cf, MOI.LessThan(3.0))

    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.LessThan{Float64}}()) == 1
    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 1

    objf = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.ResultCount()) >= 1

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 0 atol=atol rtol=rtol

        if config.basis
            @test MOI.get(model, MOI.ConstraintBasisStatus(), vc) == MOI.NONBASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.BASIC
        end
    end
end

# Modify GreaterThan and LessThan sets as bounds
function linear4test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.LessThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x = MOI.add_variable(model)
    y = MOI.add_variable(model)

    # Min  x - y
    # s.t. 0.0 <= x          (c1)
    #             y <= 0.0   (c2)

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, -1.0], [x,y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    c1 = MOI.add_constraint(model, MOI.SingleVariable(x), MOI.GreaterThan(0.0))
    @test c1.value == x.value
    c2 = MOI.add_constraint(model, MOI.SingleVariable(y), MOI.LessThan(0.0))
    @test c2.value == y.value

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end

    # Min  x - y
    # s.t. 100.0 <= x
    #               y <= 0.0
    MOI.set(model, MOI.ConstraintSet(), c1, MOI.GreaterThan(100.0))
    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end

    # Min  x - y
    # s.t. 100.0 <= x
    #               y <= -100.0
    MOI.set(model, MOI.ConstraintSet(), c2, MOI.LessThan(-100.0))
    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 200.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ -100.0 atol=atol rtol=rtol
    end
end

# Change coeffs, del constr, del var
function linear5test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    #@test MOI.get(model, MOI.SupportsDeleteVariable())
    #####################################
    # Start from simple LP
    # Solve it
    # Copy and solve again
    # Chg coeff, solve, change back solve
    # del constr and solve
    # del var and solve

    #   maximize x + y
    #
    #   s.t. 2 x + 1 y <= 4
    #        1 x + 2 y <= 4
    #        x >= 0, y >= 0
    #
    #   solution: x = 1.3333333, y = 1.3333333, objv = 2.66666666

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, vc1 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc1.value == x.value
    y = MOI.add_variable(model)
    vc2 = MOI.add_constraint(model, MOI.SingleVariable(y), MOI.GreaterThan(0.0))
    @test vc2.value == y.value

    @test MOI.get(model, MOI.NumberOfConstraints{MOI.SingleVariable,MOI.GreaterThan{Float64}}()) == 2

    @test MOI.get(model, MOI.NumberOfVariables()) == 2

    cf1 = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0,1.0], [x, y]), 0.0)
    cf2 = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,2.0], [x, y]), 0.0)

    c1 = MOI.add_constraint(model, cf1, MOI.LessThan(4.0))
    c2 = MOI.add_constraint(model, cf2, MOI.LessThan(4.0))

    @test MOI.get(model, MOI.NumberOfConstraints{MOI.ScalarAffineFunction{Float64},MOI.LessThan{Float64}}()) == 2

    objf = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], [x, y]), 0.0)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), objf)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 8/3 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), [x, y]) ≈ [4/3, 4/3] atol=atol rtol=rtol
    end

    # copy and solve again
    # missing test

    # change coeff
    #   maximize x + y
    #
    #   s.t. 2 x + 3 y <= 4
    #        1 x + 2 y <= 4
    #        x >= 0, y >= 0
    #
    #   solution: x = 2, y = 0, objv = 2

    if config.modify_lhs
        MOI.modify(model, c1, MOI.ScalarCoefficientChange(y, 3.0))
    else
        MOI.delete(model, c1)
        cf1 = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0,3.0], [x,y]), 0.0)
        c1 = MOI.add_constraint(model, cf1, MOI.LessThan(4.0))
    end

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), [x, y]) ≈ [2.0, 0.0] atol=atol rtol=rtol
    end

    # delconstrs and solve
    #   maximize x + y
    #
    #   s.t. 1 x + 2 y <= 4
    #        x >= 0, y >= 0
    #
    #   solution: x = 4, y = 0, objv = 4
    MOI.delete(model, c1)

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 4 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), [x, y]) ≈ [4.0, 0.0] atol=atol rtol=rtol
    end

    # delvars and solve
    #   maximize y
    #
    #   s.t.  2 y <= 4
    #           y >= 0
    #
    #   solution: y = 2, objv = 2
    MOI.delete(model, x)

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 2.0 atol=atol rtol=rtol
    end
end

# Modify GreaterThan and LessThan sets as linear constraints
function linear6test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x = MOI.add_variable(model)
    y = MOI.add_variable(model)

    # Min  x - y
    # s.t. 0.0 <= x          (c1)
    #             y <= 0.0   (c2)

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, -1.0], [x, y]),
                                     0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    fx = convert(MOI.ScalarAffineFunction{Float64},
                 MOI.SingleVariable(x))
    c1 = MOI.add_constraint(model, fx, MOI.GreaterThan(0.0))
    fy = convert(MOI.ScalarAffineFunction{Float64},
                 MOI.SingleVariable(y))
    c2 = MOI.add_constraint(model, fy, MOI.LessThan(0.0))

    if config.query
        @test MOI.get(model, MOI.ConstraintFunction(), c1) ≈ fx
        @test MOI.get(model, MOI.ConstraintSet(), c1) == MOI.GreaterThan(0.0)
        @test MOI.get(model, MOI.ConstraintFunction(), c2) ≈ fy
        @test MOI.get(model, MOI.ConstraintSet(), c2) == MOI.LessThan(0.0)
    end

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end

    # Min  x - y
    # s.t. 100.0 <= x
    #               y <= 0.0
    MOI.set(model, MOI.ConstraintSet(), c1, MOI.GreaterThan(100.0))

    if config.query
        @test MOI.get(model, MOI.ConstraintFunction(), c1) ≈ fx
        @test MOI.get(model, MOI.ConstraintSet(), c1) == MOI.GreaterThan(100.0)
        @test MOI.get(model, MOI.ConstraintFunction(), c2) ≈ fy
        @test MOI.get(model, MOI.ConstraintSet(), c2) == MOI.LessThan(0.0)
    end

    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end

    # Min  x - y
    # s.t. 100.0 <= x
    #               y <= -100.0
    MOI.set(model, MOI.ConstraintSet(), c2, MOI.LessThan(-100.0))

    if config.query
        @test MOI.get(model, MOI.ConstraintFunction(), c1) ≈ fx
        @test MOI.get(model, MOI.ConstraintSet(), c1) == MOI.GreaterThan(100.0)
        @test MOI.get(model, MOI.ConstraintFunction(), c2) ≈ fy
        @test MOI.get(model, MOI.ConstraintSet(), c2) == MOI.LessThan(-100.0)
    end

    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 200.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ -100.0 atol=atol rtol=rtol
    end
end

# Modify constants in Nonnegatives and Nonpositives
function linear7test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol

    # Min  x - y
    # s.t. bx <= x          (c1)
    #             y <= by   (c2)
    #
    # or, in more detail,
    #
    # Min    1 x - 1 y
    # s.t. - 1 x       <= - bx  (z)   (c1)
    #              1 y <=   by  (w)   (c2)
    #
    # with generic dual
    #
    # Max  - bx z + by w
    # s.t. -    z        == - 1     (c1)
    #                  w ==   1     (c2)
    # i.e. z == w == 1

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.VectorAffineFunction{Float64}, MOI.Nonnegatives)
    @test MOI.supports_constraint(model, MOI.VectorAffineFunction{Float64}, MOI.Nonpositives)

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x = MOI.add_variable(model)
    y = MOI.add_variable(model)

    # Min  x - y
    # s.t. 0.0 <= x          (c1)
    #             y <= 0.0   (c2)

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, -1.0], [x,y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    c1 = MOI.add_constraint(model, MOI.VectorAffineFunction([MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(1.0, x))], [0.0]), MOI.Nonnegatives(1))
    c2 = MOI.add_constraint(model, MOI.VectorAffineFunction([MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(1.0, y))], [0.0]), MOI.Nonpositives(1))

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end

    # Min  x - y
    # s.t. 100.0 <= x
    #               y <= 0.0

    if config.modify_lhs
        MOI.modify(model, c1, MOI.VectorConstantChange([-100.0]))
    else
        MOI.delete(model, c1)
        c1 = MOI.add_constraint(model, MOI.VectorAffineFunction([MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(1.0, x))], [-100.0]), MOI.Nonnegatives(1))
    end

    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end

    # Min  x - y
    # s.t. 100.0 <= x
    #               y <= -100.0

    if config.modify_lhs
        MOI.modify(model, c2, MOI.VectorConstantChange([100.0]))
    else
        MOI.delete(model, c2)
        c2 = MOI.add_constraint(model, MOI.VectorAffineFunction([MOI.VectorAffineTerm(1, MOI.ScalarAffineTerm(1.0, y))], [100.0]), MOI.Nonpositives(1))
    end

    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 200.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 100.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ -100.0 atol=atol rtol=rtol
    end
end

# infeasible problem
function linear8atest(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # min x
    # s.t. 2x+y <= -1
    # x,y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, bndx = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test bndx.value == x.value
    y, bndy = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test bndy.value == y.value
    c = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0,1.0], [x,y]), 0.0), MOI.LessThan(-1.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE ||
            MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE_OR_UNBOUNDED
        if config.duals && config.infeas_certificates
            # solver returned an infeasibility ray
            @test MOI.get(model, MOI.ResultCount()) >= 1

            @test MOI.get(model, MOI.DualStatus()) == MOI.INFEASIBILITY_CERTIFICATE
            cd = MOI.get(model, MOI.ConstraintDual(), c)
            @test cd < -atol
            # TODO: farkas dual on bounds - see #127
            # xd = MOI.get(model, MOI.ConstraintDual(), bndx)
            # yd = MOI.get(model, MOI.ConstraintDual(), bndy)
            # @test xd > atol
            # @test yd > atol
            # @test yd ≈ -cd atol=atol rtol=rtol
            # @test xd ≈ -2cd atol=atol rtol=rtol
        else
            # solver returned nothing
            @test MOI.get(model, MOI.ResultCount()) == 0
        end
    end
end

# unbounded problem
function linear8btest(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # min -x-y
    # s.t. -x+2y <= 0
    # x,y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, vc1 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc1.value == x.value
    y, vc2 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc2.value == y.value
    MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0,2.0], [x,y]), 0.0), MOI.LessThan(0.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0, -1.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == MOI.DUAL_INFEASIBLE ||
            MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE_OR_UNBOUNDED
        if config.infeas_certificates
            # solver returned an unbounded ray
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.PrimalStatus()) == MOI.INFEASIBILITY_CERTIFICATE
        else
            # solver returned nothing
            @test MOI.get(model, MOI.ResultCount()) == 0
        end
    end
end

# unbounded problem with unique ray
function linear8ctest(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # min -x-y
    # s.t. x-y == 0
    # x,y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.EqualTo{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, vc1 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc1.value == x.value
    y, vc2 = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test vc2.value == y.value
    MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,-1.0], [x,y]), 0.0), MOI.EqualTo(0.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([-1.0, -1.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == MOI.DUAL_INFEASIBLE ||
            MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE_OR_UNBOUNDED
        if config.infeas_certificates
            # solver returned an unbounded ray
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.PrimalStatus()) == MOI.INFEASIBILITY_CERTIFICATE
            ray = MOI.get(model, MOI.VariablePrimal(), [x,y])
            @test ray[1] ≈ ray[2] atol=atol rtol=rtol
        else
            # solver returned nothing
            @test MOI.get(model, MOI.ResultCount()) == 0
        end
    end
end

# add_constraints
function linear9test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    #   maximize 1000 x + 350 y
    #
    #       s.t.                x >= 30
    #                           y >= 0
    #                 x -   1.5 y >= 0
    #            12   x +   8   y <= 1000
    #            1000 x + 300   y <= 70000
    #
    #   solution: (59.0909, 36.3636)
    #   objv: 71818.1818

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    xy, vc12 = MOI.add_constrained_variables(model,
        [MOI.GreaterThan(30.0), MOI.GreaterThan(0.0)]
    )
    x, y = xy
    @test vc12[1].value == x.value
    @test vc12[2].value == y.value

    c1 = MOI.add_constraints(model,
        [MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, -1.5], [x, y]), 0.0)],
        [MOI.GreaterThan(0.0)]
    )

    c23 = MOI.add_constraints(model,
        [
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([12.0, 8.0], [x, y]), 0.0),
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1_000.0, 300.0], [x, y]), 0.0)
        ],
        [
            MOI.LessThan(1_000.0),
            MOI.LessThan(70_000.0)
        ]
    )

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
                      MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1_000.0, 350.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 79e4/11 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 650/11 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 400/11 atol=atol rtol=rtol

        if config.basis
            @test MOI.get(model, MOI.ConstraintBasisStatus(), vc12[1]) == MOI.BASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), vc12[2]) == MOI.BASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c1[1]) == MOI.BASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c23[1]) == MOI.NONBASIC
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c23[2]) == MOI.NONBASIC
        end
    end
end

# ranged constraints
function linear10test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    #   maximize x + y
    #
    #       s.t.  5 <= x + y <= 10
    #                  x,  y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.Interval{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    xy, vc = MOI.add_constrained_variables(model,
        [MOI.GreaterThan(0.0), MOI.GreaterThan(0.0)]
    )
    x, y = xy
    @test vc[1].value == x.value
    @test vc[2].value == y.value

    c = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x,y]), 0.0), MOI.Interval(5.0, 10.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 10.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 10 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 10.0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1 atol=atol rtol=rtol
        end

        if config.basis
            # There are multiple optimal bases. Either x or y can be in the optimal basis.
            @test (MOI.get(model, MOI.ConstraintBasisStatus(), vc[1]) == MOI.BASIC ||
                   MOI.get(model, MOI.ConstraintBasisStatus(), vc[2])== MOI.BASIC)
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC_AT_UPPER
        end
    end

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 5.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 5 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 5.0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ 1 atol=atol rtol=rtol
        end

        if config.basis
            # There are multiple optimal bases. Either x or y can be in the optimal basis."
            @test (MOI.get(model, MOI.ConstraintBasisStatus(), vc[1]) == MOI.BASIC ||
                   MOI.get(model, MOI.ConstraintBasisStatus(), vc[2])== MOI.BASIC)
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC_AT_LOWER
        end
    end

    MOI.set(model, MOI.ConstraintSet(), c, MOI.Interval(2.0, 12.0))

    if config.query
        @test MOI.get(model, MOI.ConstraintSet(), c) == MOI.Interval(2.0, 12.0)
    end

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 2 atol=atol rtol=rtol

        if config.basis
            # There are multiple optimal bases. Either x or y can be in the optimal basis.
            @test (MOI.get(model, MOI.ConstraintBasisStatus(), vc[1]) == MOI.BASIC ||
                   MOI.get(model, MOI.ConstraintBasisStatus(), vc[2])== MOI.BASIC)
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC_AT_LOWER
        end

        if config.duals
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 2.0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ 1 atol=atol rtol=rtol
        end
    end

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 12.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 12 atol=atol rtol=rtol

        if config.basis
            # There are multiple optimal bases. Either x or y can be in the optimal basis.
            @test (MOI.get(model, MOI.ConstraintBasisStatus(), vc[1]) == MOI.BASIC ||
                   MOI.get(model, MOI.ConstraintBasisStatus(), vc[2])== MOI.BASIC)
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC_AT_UPPER
        end
    end
end

# inactive ranged constraints
function linear10btest(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    #   minimize x + y
    #
    #       s.t.  -1 <= x + y <= 10
    #                   x,  y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.Interval{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    xy, vc = MOI.add_constrained_variables(model,
        [MOI.GreaterThan(0.0), MOI.GreaterThan(0.0)]
    )
    x, y = xy
    @test vc[1].value == x.value
    @test vc[2].value == y.value

    c = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x,y]), 0.0), MOI.Interval(-1.0, 10.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x, y]), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 0.0 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ 0.0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc[1]) ≈ 1.0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), vc[2]) ≈ 1.0 atol=atol rtol=rtol
        end

        if config.basis
            @test (MOI.get(model, MOI.ConstraintBasisStatus(), vc[1]) == MOI.NONBASIC)
            @test (MOI.get(model, MOI.ConstraintBasisStatus(), vc[1]) == MOI.NONBASIC)
            @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.BASIC
        end
    end
end

# changing constraint sense
function linear11test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # simple 2 variable, 1 constraint problem
    #
    # starts with
    #
    # min x + y
    # st   x + y >= 1
    #      x + y >= 2
    # sol: x+y = 2 (degenerate)
    #
    # with dual
    #
    # max  w + 2z
    # st   w +  z == 1
    #      w +  z == 1
    #      w, z >= 0
    # sol: z = 1, w = 0
    #
    # tranforms problem into:
    #
    # min x + y
    # st   x + y >= 1
    #      x + y <= 2
    # sol: x+y = 1 (degenerate)
    #
    # with dual
    #
    # max  w + 2z
    # st   w +  z == 1
    #      w +  z == 1
    #      w >= 0, z <= 0
    # sol: w = 1, z = 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    v = MOI.add_variables(model, 2)

    c1 = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], v), 0.0), MOI.GreaterThan(1.0))
    c2 = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], v), 0.0), MOI.GreaterThan(2.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,1.0], v), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2.0 atol=atol rtol=rtol
    end

    c3 = MOI.transform(model, c2, MOI.LessThan(2.0))

    @test isa(c3, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64}})
    @test MOI.is_valid(model, c2) == false
    @test MOI.is_valid(model, c3) == true

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 1.0 atol=atol rtol=rtol
    end
end

# infeasible problem with 2 linear constraints
function linear12test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # min x
    # s.t. 2x-3y <= -7
    #      y <= 2
    # x,y >= 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, bndx = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test bndx.value == x.value
    y, bndy = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test bndy.value == y.value

    c1 = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0,-3.0], [x,y]), 0.0), MOI.LessThan(-7.0))
    c2 = MOI.add_constraint(model, MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, y)], 0.0), MOI.LessThan(2.0))
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE ||
            MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE_OR_UNBOUNDED
        if config.duals && config.infeas_certificates
            # solver returned an infeasibility ray
            @test MOI.get(model, MOI.ResultCount()) >= 1
            @test MOI.get(model, MOI.DualStatus()) == MOI.INFEASIBILITY_CERTIFICATE
            cd1 = MOI.get(model, MOI.ConstraintDual(), c1)
            cd2 = MOI.get(model, MOI.ConstraintDual(), c2)
            bndxd = MOI.get(model, MOI.ConstraintDual(), bndx)
            bndyd = MOI.get(model, MOI.ConstraintDual(), bndy)
            @test cd1 < - atol
            @test cd2 < - atol
            @test - 3 * cd1 + cd2 ≈ -bndyd atol=atol rtol=rtol
            @test 2 * cd1 ≈ -bndxd atol=atol rtol=rtol
            @test -7 * cd1 + 2 * cd2 > atol
        else
            # solver returned nothing
            @test MOI.get(model, MOI.ResultCount()) == 0
        end
    end
end

# feasibility problem
function linear13test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # find x, y
    # s.t. 2x + 3y >= 1
    #      x - y == 0

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.EqualTo{Float64})
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x = MOI.add_variable(model)
    y = MOI.add_variable(model)
    c1 = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0,3.0], [x,y]), 0.0), MOI.GreaterThan(1.0))
    c2 = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0,-1.0], [x,y]), 0.0), MOI.EqualTo(0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.FEASIBILITY_SENSE)
    @test MOI.get(model, MOI.ObjectiveSense()) == MOI.FEASIBILITY_SENSE

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)
        @test MOI.get(model, MOI.ResultCount()) > 0

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        xsol = MOI.get(model, MOI.VariablePrimal(), x)
        ysol = MOI.get(model, MOI.VariablePrimal(), y)

        c1sol = 2 * xsol + 3 * ysol
        @test c1sol >= 1 || isapprox(c1sol, 1.0, atol=atol, rtol=rtol)
        @test xsol - ysol ≈ 0 atol=atol rtol=rtol

        c1primval = MOI.get(model, MOI.ConstraintPrimal(), c1)
        @test c1primval >= 1 || isapprox(c1sol, 1.0, atol=atol, rtol=rtol)

        @test MOI.get(model, MOI.ConstraintPrimal(), c2) ≈ 0 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.ConstraintDual(), c1) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c2) ≈ 0 atol=atol rtol=rtol
        end
    end
end

# Deletion of vector of variables
function linear14test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # max x + 2y + 3z + 4
    # s.t. 3x + 2y + z <= 2
    #      x, y, z >= 0
    #      z <= 1

    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.GreaterThan{Float64})
    @test MOI.supports_constraint(model, MOI.SingleVariable, MOI.LessThan{Float64})

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x, clbx = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test clbx.value == x.value
    y, clby = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test clby.value == y.value
    z, clbz = MOI.add_constrained_variable(model, MOI.GreaterThan(0.0))
    @test clbz.value == z.value
    cubz = MOI.add_constraint(model, MOI.SingleVariable(z), MOI.LessThan(1.0))
    @test cubz.value == z.value

    c = MOI.add_constraint(model, MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([3.0, 2.0, 1.0], [x, y, z]), 0.0), MOI.LessThan(2.0))

    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 2.0, 3.0], [x, y, z]), 4.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 8 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 1/2 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), z) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 2 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), clbx) ≈ 0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), clby) ≈ 1/2 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), clbz) ≈ 1 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), cubz) ≈ 1 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 8 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1 atol=atol rtol=rtol

            # reduced costs
            @test MOI.get(model, MOI.ConstraintDual(), clbx) ≈ 2 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), clby) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), clbz) ≈ 0 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), cubz) ≈ -2 atol=atol rtol=rtol

            if config.basis
                @test MOI.get(model, MOI.ConstraintBasisStatus(), clbx) == MOI.NONBASIC
                @test MOI.get(model, MOI.ConstraintBasisStatus(), clby) == MOI.BASIC
                @test MOI.get(model, MOI.ConstraintBasisStatus(), clbz) == MOI.BASIC
                @test MOI.get(model, MOI.ConstraintBasisStatus(), cubz) == MOI.NONBASIC
                @test MOI.get(model, MOI.ConstraintBasisStatus(), c) == MOI.NONBASIC
            end
        end
    end

    MOI.delete(model, [x, z])

    if config.solve
        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 6 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 1 atol=atol rtol=rtol

        @test MOI.get(model, MOI.ConstraintPrimal(), c) ≈ 2 atol=atol rtol=rtol
        @test MOI.get(model, MOI.ConstraintPrimal(), clby) ≈ 1 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 6 atol=atol rtol=rtol
            @test MOI.get(model, MOI.ConstraintDual(), c) ≈ -1 atol=atol rtol=rtol

            # reduced costs
            @test MOI.get(model, MOI.ConstraintDual(), clby) ≈ 0 atol=atol rtol=rtol
        end
    end
end

# Empty vector affine function rows (LQOI Issue #48)
function linear15test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # minimize 0
    # s.t. 0 == 0
    #      x == 1
    @test MOIU.supports_default_copy_to(model, #=copy_names=# false)
    @test MOI.supports(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}())
    @test MOI.supports(model, MOI.ObjectiveSense())
    @test MOI.supports_constraint(model, MOI.VectorAffineFunction{Float64}, MOI.Zeros)

    MOI.empty!(model)
    @test MOI.is_empty(model)

    x = MOI.add_variables(model, 1)
    # Create a VectorAffineFunction with two rows, but only
    # one term, belonging to the second row. The first row,
    # which is empty, is essentially a constraint that 0 == 0.
    c = MOI.add_constraint(model,
        MOI.VectorAffineFunction(
            MOI.VectorAffineTerm.(2, MOI.ScalarAffineTerm.([1.0], x)),
            zeros(2)
        ),
        MOI.Zeros(2)
    )

    MOI.set(model,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
        MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([0.0], x), 0.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)

    if config.solve
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

        MOI.optimize!(model)

        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status

        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0 atol=atol rtol=rtol

        @test MOI.get(model, MOI.VariablePrimal(), x[1]) ≈ 0 atol=atol rtol=rtol

        if config.duals
            @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
            @test MOI.get(model, MOI.DualObjectiveValue()) ≈ 0 atol=atol rtol=rtol
        end
    end
end

# This test can be passed by solvers that don't support VariablePrimalStart
# because copy_to drops start information with a warning.
function partial_start_test(model::MOI.ModelLike, config::TestConfig)
    atol = config.atol
    rtol = config.rtol
    # maximize 2x + y
    # s.t. x + y <= 1
    #      x, y >= 0
    #      x starts at 1.0. Start point for y is unspecified.
    MOI.empty!(model)
    @test MOI.is_empty(model)

    x = MOI.add_variable(model)
    y = MOI.add_variable(model)

    MOI.set(model, MOI.VariablePrimalStart(), x, 1.0)

    MOI.add_constraint(model, x, MOI.GreaterThan(0.0))
    MOI.add_constraint(model, y, MOI.GreaterThan(0.0))
    obj = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([2.0, 1.0], [x, y]),
                                   0.0)
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    x_plus_y = MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.(1.0, [x, y]), 0.0)
    MOI.add_constraint(model, x_plus_y, MOI.LessThan(1.0))

    if config.solve
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 2.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), x) ≈ 1.0 atol=atol rtol=rtol
        @test MOI.get(model, MOI.VariablePrimal(), y) ≈ 0.0 atol=atol rtol=rtol
    end
end

const contlineartests = Dict("linear1" => linear1test,
                             "linear2" => linear2test,
                             "linear3" => linear3test,
                             "linear4" => linear4test,
                             "linear5" => linear5test,
                             "linear6" => linear6test,
                             "linear7" => linear7test,
                             "linear8a" => linear8atest,
                             "linear8b" => linear8btest,
                             "linear8c" => linear8ctest,
                             "linear9" => linear9test,
                             "linear10" => linear10test,
                             "linear10b" => linear10btest,
                             "linear11" => linear11test,
                             "linear12" => linear12test,
                             "linear13" => linear13test,
                             "linear14" => linear14test,
                             "linear15" => linear15test,
                             "partial_start" => partial_start_test)

@moitestset contlinear
