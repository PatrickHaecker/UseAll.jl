using JET, Test, TOML, UseAll

@testset "JET" begin
    # The optional extensions intentionally rely on private APIs, so keep JET
    # focused on the stable core helpers.
    JET.@test_call UseAll.splitmodpath(:(Base.Iterators))
    JET.@test_call UseAll.allnames(TOML)
    JET.@test_call collect(UseAll.usefulnames(TOML, Main))
end
