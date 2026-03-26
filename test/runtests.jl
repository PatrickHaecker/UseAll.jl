using UseAll, Test, TOML

import UseAll: allnames

@testset "UseAll" begin
    @testset "@useall with no arguments" begin
        @test_throws LoadError @eval @useall
    end

    @testset "@useall with a single package" begin
        @eval module _TestSingle
            using UseAll, TOML
            @useall TOML
        end
        exported = allnames(_TestSingle)
        @test :parsefile in exported
        @test :parse in exported
    end

    @testset "@useall with submodule" begin
        @eval module _TestSub
            using UseAll
            @useall Base.Iterators
        end
        exported = allnames(_TestSub)
        @test :countfrom in exported
        @test :cycle in exported
    end

    @testset "@useall with package and submodule" begin
        @eval module _TestMulti
            using UseAll, TOML
            @useall TOML Base.Iterators
        end
        exported = allnames(_TestMulti)
        @test :parsefile in exported  # from TOML
        @test :countfrom in exported  # from Base.Iterators
    end

    @testset "@useall with multiple packages" begin
        @eval module _TestMultiPkg
            using UseAll, TOML, Test
            @useall TOML Test
        end
        exported = allnames(_TestMultiPkg)
        @test :parsefile in exported  # from TOML
        @test :detect_ambiguities in exported  # from Test
    end

    @testset "does not import eval/include" begin
        useful = UseAll.usefulnames(TOML)
        syms = [s.args[1] for s in useful]
        @test :eval ∉ syms
        @test :include ∉ syms
    end

    @testset "does not import hidden names" begin
        useful = UseAll.usefulnames(TOML)
        syms = [s.args[1] for s in useful]
        @test all(s -> !startswith(string(s), '#'), syms)
    end

    @testset "splitmodpath" begin
        @test UseAll.splitmodpath(:Foo) == (:Foo,)
        @test UseAll.splitmodpath(:(Base.Iterators)) == (:Base, :Iterators)
        @test UseAll.splitmodpath(:(A.B.C)) == (:A, :B, :C)
    end
end
