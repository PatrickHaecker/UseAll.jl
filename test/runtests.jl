using Aqua, Revise, UseAll, Test, TOML

@testset "UseAll" begin
    @testset "@useall with no arguments" begin
        @test_throws LoadError @eval @useall
    end

    @testset "@useall with a single package" begin
        @eval module _TestSingle
            using UseAll, TOML
            @useall TOML
        end
        @test isdefined(_TestSingle, :parsefile)
        @test isdefined(_TestSingle, :parse)
    end

    @testset "@useall with submodule" begin
        @eval module _TestSub
            using UseAll
            @useall Base.Iterators
        end
        @test isdefined(_TestSub, :countfrom)
        @test isdefined(_TestSub, :cycle)
    end

    @testset "@useall with package and submodule" begin
        @eval module _TestMulti
            using UseAll, TOML
            @useall TOML Base.Iterators
        end
        @test isdefined(_TestMulti, :parsefile)   # from TOML
        @test isdefined(_TestMulti, :countfrom)    # from Base.Iterators
    end

    @testset "@useall with multiple packages" begin
        @eval module _TestMultiPkg
            using UseAll, TOML, Test
            @useall TOML Test
        end
        @test isdefined(_TestMultiPkg, :parsefile)          # from TOML
        @test isdefined(_TestMultiPkg, :detect_ambiguities)  # from Test
    end

    @testset "@useall with submodule of current module" begin
        @eval module _TestSubOwn
            module Inner
                export exported_func
                exported_func() = 1
                private_func() = 2
            end
            using UseAll
            @useall Inner
        end
        @test isdefined(_TestSubOwn, :exported_func)
        @test isdefined(_TestSubOwn, :private_func)
    end

    @testset "@useall using .SubModule" begin
        @eval module _TestUsingDot
            module Inner
                export exported_func_ud
                exported_func_ud() = 1
                private_func_ud() = 2
            end
            using UseAll
            @useall using .Inner
        end
        @test isdefined(_TestUsingDot, :exported_func_ud)
        @test isdefined(_TestUsingDot, :private_func_ud)
    end

    @testset "does not import eval/include" begin
        useful = UseAll.usefulnames(TOML)
        syms = [s.args[1] for s in useful]
        @test :eval ∉ syms
        @test :include ∉ syms
    end

    @testset "@usepublic with a single package" begin
        @eval module _TestPubSingle
            using UseAll: @usepublic
            using Test
            @usepublic Test
        end
        @test isdefined(_TestPubSingle, :detect_ambiguities)
    end

    @testset "@usepublic does not import private names" begin
        @eval module _TestPubPrivate
            module Inner
                export exported_func_pp
                exported_func_pp() = 1
                private_func_pp() = 2
            end
            using UseAll: @usepublic
            @usepublic Inner
        end
        @test isdefined(_TestPubPrivate, :exported_func_pp)
        @test !isdefined(_TestPubPrivate, :private_func_pp)
    end

    @testset "@usepublic with submodule" begin
        @eval module _TestPubSub
            using UseAll: @usepublic
            @usepublic Base.Iterators
        end
        # Base.Iterators exports some names
        exported = Base.names(Base.Iterators)
        @test any(s -> isdefined(_TestPubSub, s), exported)
    end

    @testset "@usepublic using .SubModule" begin
        @eval module _TestPubUsingDot
            module Inner
                export exported_func_pud
                exported_func_pud() = 1
                private_func_pud() = 2
            end
            using UseAll: @usepublic
            @usepublic using .Inner
        end
        @test isdefined(_TestPubUsingDot, :exported_func_pud)
        @test !isdefined(_TestPubUsingDot, :private_func_pud)
    end

    @testset "@usepublic with no arguments" begin
        @test_throws LoadError @eval UseAll.@usepublic
    end

    @testset "publicnames helper" begin
        pub = UseAll.publicnames(Test)
        @test :Test in pub
        @test :detect_ambiguities in pub
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

    @testset "@useall survives broken Revise.add_callback" begin
        # Revise.add_callback throws for untrackable modules like Base.Iterators.
        # This verifies the try-catch in UseAllReviseExt keeps @useall working.
        @eval module _TestBrokenCallback
            using UseAll
            @useall Base.Iterators
        end
        @test isdefined(_TestBrokenCallback, :countfrom)
    end

    @testset "Revise integration" begin
        dir = mktempdir()
        mkpath(joinpath(dir, "ReviseTestPkg", "src"))
        write(joinpath(dir, "ReviseTestPkg", "Project.toml"), """
            name = "ReviseTestPkg"
            uuid = "12345678-1234-1234-1234-123456789abc"
            """)
        srcfile = joinpath(dir, "ReviseTestPkg", "src", "ReviseTestPkg.jl")
        write(srcfile, """
            module ReviseTestPkg
            export original_func
            original_func() = 1
            end
            """)

        push!(LOAD_PATH, dir)
        @eval @useall ReviseTestPkg

        @test isdefined(@__MODULE__, :original_func)
        @test !isdefined(@__MODULE__, :added_func)

        write(srcfile, """
            module ReviseTestPkg
            export original_func, added_func
            original_func() = 1
            added_func() = 42
            end
            """)

        # Manually enqueue for revision (file watchers don't trigger in batch mode).
        id = Base.PkgId(ReviseTestPkg)
        pkgdata = Revise.pkgdatas[id]
        push!(Revise.revision_queue, (pkgdata, first(Revise.srcfiles(pkgdata))))
        Revise.revise()

        @test isdefined(@__MODULE__, :added_func)
        @test Base.invokelatest(Main.ReviseTestPkg.added_func) == 42

        pop!(LOAD_PATH)
    end

    # Constructing a PromptState requires REPL internals, so these tests are version-gated.
    if VERSION >= v"1.12" && !isnothing(Base.identify_package("REPL"))
        @testset "REPL tab completion" begin
            using REPL, REPL.LineEdit
            ext = Base.get_extension(UseAll, :UseAllREPLExt)
            function _test_completions(input)
                cp = ext.UseAllCompletionProvider(REPL.REPLCompletionProvider())
                prompt = LineEdit.Prompt("julia> ")
                buf = IOBuffer(input)
                seek(buf, length(input))
                terminal = Base.Terminals.TerminalBuffer(IOBuffer())
                s = LineEdit.PromptState(terminal, prompt, buf, :off, nothing, IOBuffer[], 0,
                                         LineEdit.InputAreaState(0, 0), -1,
                                         Base.Threads.SpinLock(), -Inf, -Inf, nothing)
                comps, _, _ = LineEdit.complete_line(cp, s, Main)
                return [c.completion for c in comps]
            end
            @test "TOML" in _test_completions("@useall TO")
            @test "Iterators" in _test_completions("@useall Base.Ite")
            @test "TOML" in _test_completions("@useall Test TO")
            @test "TOML" in _test_completions("@usepublic TO")
            @test "Iterators" in _test_completions("@usepublic Base.Ite")
            @test "println" in _test_completions("printl")  # normal completion unaffected
        end
    end

    @testset "Aqua" begin
        Aqua.test_all(UseAll)
    end
end
