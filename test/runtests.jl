using Revise, UseAll, Test, TOML, REPL

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

    @testset "@useall survives broken Revise.add_callback" begin
        # Revise.add_callback throws for untrackable modules like Base.Iterators.
        # This verifies the try-catch in UseAllReviseExt keeps @useall working.
        @eval module _TestBrokenCallback
            using UseAll
            @useall Base.Iterators
        end
        @test :countfrom in allnames(_TestBrokenCallback)
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

    @testset "REPL tab completion" begin
        using REPL.LineEdit
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
        @test "println" in _test_completions("printl")  # normal completion unaffected
    end
end
