using Test

@testset "BridgeOptimizer" begin
    include("bridge_optimizer.jl")
end
@testset "LazyBridgeOptimizer" begin
    include("lazy_bridge_optimizer.jl")
end
@testset "Variable bridges" begin
    include("Variable/Variable.jl")
end
@testset "Constraint bridges" begin
    include("Constraint/Constraint.jl")
end
