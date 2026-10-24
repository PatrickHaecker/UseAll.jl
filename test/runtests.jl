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

    @testset "@useall with nested submodule of current module" begin
        @eval module _TestNested
            module Tools
                module Inner
                    nested_func() = 1
                end
            end
            using UseAll
            @useall Tools.Inner
        end
        @test isdefined(_TestNested, :nested_func)
    end

    @testset "@useall using .SubModule, ..SiblingModule" begin
        @eval module _TestParent
            module Sibling
                sibling_func() = 1
            end
            module Child
                module Own
                    own_func() = 2
                end
                using UseAll
                @useall using .Own, ..Sibling
            end
        end
        @test isdefined(_TestParent.Child, :sibling_func)
        @test isdefined(_TestParent.Child, :own_func)
    end

    @testset "@useall with module bound in current module" begin
        @eval module _TestBound
            using UseAll
            @useall Iterators   # Bound through `using Base`.
        end
        @test isdefined(_TestBound, :countfrom)
    end

    @testset "@useall lookup order" begin
        # A submodule of the current module comes before a package with the same name.
        @eval module _TestSubFirst
            module TOML
                sub_first_func() = 1
            end
            using UseAll
            @useall TOML
        end
        @test isdefined(_TestSubFirst, :sub_first_func)
        @test !isdefined(_TestSubFirst, :parsefile)
        # A package comes before another module bound in the current module.
        @eval module _TestPackageFirst
            const TOML = Base.Iterators
            using UseAll
            @useall TOML
        end
        @test isdefined(_TestPackageFirst, :parsefile)
        @test !isdefined(_TestPackageFirst, :countfrom)
    end

    @testset "@useall with package not loaded in Main" begin
        dir = mktempdir()
        mkpath(joinpath(dir, "UseAllTestPkg", "src"))
        write(joinpath(dir, "UseAllTestPkg", "Project.toml"), """
            name = "UseAllTestPkg"
            uuid = "0b6c3e0c-7e2b-4a8e-9a43-2d1f5c6b7a01"
            """)
        write(joinpath(dir, "UseAllTestPkg", "src", "UseAllTestPkg.jl"), """
            module UseAllTestPkg
            module Sub
            sub_func() = 1
            end
            end
            """)
        push!(LOAD_PATH, dir)
        try
            @eval module _TestNotInMain
                using UseAll
                @useall UseAllTestPkg.Sub
            end
            @test isdefined(_TestNotInMain, :sub_func)
            @test !isdefined(Main, :UseAllTestPkg)
        finally
            pop!(LOAD_PATH)
        end
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
        @test UseAll.splitmodpath(:Foo) == (0, [:Foo])
        @test UseAll.splitmodpath(:(Base.Iterators)) == (0, [:Base, :Iterators])
        @test UseAll.splitmodpath(:(A.B.C)) == (0, [:A, :B, :C])
        @test UseAll.splitmodpath(Meta.parse("using ..A.B").args[1]) == (2, [:A, :B])
        @test isnothing(UseAll.splitmodpath(:(f(x))))
        @test_throws LoadError @eval @useall f(x)
    end

    @testset "@useall with a module Revise can't track" begin
        # Revise has no recipe to track modules without a package or file, so UseAll skips the callback silently.
        @eval module _TestUntracked
            module Source
                export untracked_name
                const untracked_name = 1
            end
        end
        @test_logs min_level = Base.CoreLogging.Warn @eval module _TestUntrackedUser
            using UseAll
            @useall Main._TestUntracked.Source
        end
        @test isdefined(_TestUntrackedUser, :untracked_name)
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
        # Same target name in different parents, and both name selections for one target, need separate callbacks.
        @eval module _ReviseA
            module Target
                using UseAll
                @useall ReviseTestPkg
            end
        end
        @eval module _ReviseB
            module Target
                using UseAll
                @useall ReviseTestPkg
            end
        end
        @eval UseAll.@usepublic ReviseTestPkg

        @test isdefined(@__MODULE__, :original_func)
        @test !isdefined(@__MODULE__, :added_func)

        write(srcfile, """
            module ReviseTestPkg
            export original_func, added_func
            original_func() = 1
            added_func() = 42
            added_private() = 43
            end
            """)

        # Manually enqueue the revision and the callbacks like Revise's file watcher does, which is not reliable in
        # batch mode.
        id = Base.PkgId(ReviseTestPkg)
        pkgdata = Revise.pkgdatas[id]
        file = first(Revise.srcfiles(pkgdata))
        push!(Revise.revision_queue, (pkgdata, file))
        union!(Revise.user_callbacks_queue, Revise.user_callbacks_by_file[joinpath(Revise.basedir(pkgdata), file)])
        Revise.revise()

        @test isdefined(@__MODULE__, :added_func)
        @test Base.invokelatest(Main.ReviseTestPkg.added_func) == 42
        @test isdefined(@__MODULE__, :added_private)
        @test isdefined(_ReviseA.Target, :added_private)
        @test isdefined(_ReviseB.Target, :added_private)

        pop!(LOAD_PATH)
    end

    if !isnothing(Base.identify_package("REPL"))
        @testset "REPL tab completion" begin
            using REPL, REPL.LineEdit
            ext = Base.get_extension(UseAll, :UseAllREPLExt)
            function _complete(input; native=false)
                wrapped = REPL.REPLCompletionProvider()
                cp = native ? wrapped : ext.UseAllCompletionProvider(wrapped)
                terminal = REPL.Terminals.TerminalBuffer(IOBuffer())
                # `init_state` is REPL-internal, but unlike the `PromptState` fields it is stable since Julia 1.10.
                s = LineEdit.init_state(terminal, LineEdit.Prompt("julia> "))
                write(s.input_buffer, input)
                comps, region, _ = LineEdit.complete_line(cp, s, Main)
                # Julia 1.12 replaced the returned strings by `NamedCompletion`s.
                return [c isa AbstractString ? c : c.completion for c in comps], region
            end
            _test_completions(input) = first(_complete(input))
            # Packages that are not loaded into `Main`, so only the `using` completion finds them, not the fallback.
            dir = mktempdir()
            for name in ("UseAllCompletionPkg", "UseAllΩPkg")
                mkpath(joinpath(dir, name, "src"))
                write(joinpath(dir, name, "src", "$name.jl"), "module $name end\n")
            end
            push!(LOAD_PATH, dir)
            try
                @test "TOML" in _test_completions("@useall TO")
                @test "Iterators" in _test_completions("@useall Base.Ite")
                @test "TOML" in _test_completions("@useall Test TO")
                @test "TOML" in _test_completions("@usepublic TO")
                @test "Iterators" in _test_completions("@usepublic Base.Ite")
                @test "UseAllCompletionPkg" in _test_completions("@useall UseAllCompletionP")
                @test "UseAllCompletionPkg" in _test_completions("@usepublic Test UseAllCompletionP")
                # Code after the macro call is completed normally.
                @test "println" in _test_completions("@useall TOML; printl")
                @test "println" in _test_completions("@useall TOML\nprintl")
                # A multibyte character before the cursor.
                comps, region = _complete("@useall UseAllΩ")
                @test "UseAllΩPkg" in comps
                @test region == (ext.HAS_NAMED_COMPLETION ? (8 => 8 + ncodeunits("UseAllΩ")) : "UseAllΩ")
                # Not inside comments, strings or command literals.
                for prefix in ("# ", "#= ", "\"", "raw\"", "`echo ")
                    @test "UseAllCompletionPkg" ∉ _test_completions(prefix * "@useall UseAllCompletionP")
                end
                @test "UseAllCompletionPkg" in _test_completions("@useall using .A, UseAllCompletionP")
                # Qualified and parenthesized macro calls.
                @test "UseAllCompletionPkg" in _test_completions("@UseAll.usepublic UseAllCompletionP")
                @test "UseAllCompletionPkg" in _test_completions("@useall(UseAllCompletionP")
                @test "UseAllCompletionPkg" in _test_completions("UseAll.@usepublic(TOML,\n UseAllCompletionP")
                @test "UseAllCompletionPkg" in _test_completions("@useall(\n  # packages\n  UseAllCompletionP")
                @test "UseAllCompletionPkg" in _test_completions("@useall ((UseAllCompletionP")
                @test "UseAllCompletionPkg" in _test_completions("@Main.useall.usepublic UseAllCompletionP")
                # Modules bound in `Main` are completed as first names, too, also without a prefix.
                @eval Main module UseAllBoundCompletion
                    module Inner end
                end
                @test "UseAllBoundCompletion" in _test_completions("@useall UseAllBoundCompl")
                @test "UseAllBoundCompletion" in _test_completions("@usepublic Test UseAllBoundCompl")
                @test "Iterators" in _test_completions("@useall Iter")
                for input in ("@useall ", "@useall TOML ", "@usepublic ")
                    @test "UseAllBoundCompletion" in _test_completions(input)
                end
                # A space after a dot continues the path.
                comps, region = _complete("@useall UseAllBoundCompletion. Inn")
                @test "Inner" in comps
                @test region == (ext.HAS_NAMED_COMPLETION ? (31 => 34) : "Inn")
                @test ext.useall_argument("@useall Base.") == "Base."
                @test ext.useall_argument("@useall A, B") == "B"
                @test ext.useall_argument("@useall Ω, Ωx") == "Ωx"
                @test ext.useall_argument("@useall\u00a0A,\u3000B") == "B"
                @test ext.useall_argument("@useall A. B .C") == ".C"
                @test ext.useall_argument("@useall using ..A. B") == "..A.B"
                @test ext.useall_argument("@Main.UseAll.useall A") == "A"
                @test ext.useall_argument("@useall(A,\n B") == "B"
                # Comments and grouping parentheses, which the parser drops.
                @test ext.useall_argument("@useall(\n  # c\n  Lin") == "Lin"
                @test ext.useall_argument("@useall(#= c =# Lin") == "Lin"
                @test ext.useall_argument("@useall A #=c=# B") == "B"
                @test ext.useall_argument("@useall A. #=c=# B") == "A.B"
                @test isnothing(ext.useall_argument("@useall A # c"))
                @test isnothing(ext.useall_argument("@useall A #= c"))
                @test ext.useall_argument("@useall ((Lin") == "Lin"
                @test ext.useall_argument("@useall((A), B") == "B"
                @test ext.useall_argument("@useall (A) B") == "B"
                @test isnothing(ext.useall_argument("@useall (A)"))
                @test isnothing(ext.useall_argument("@useall (A)B"))
                @test isnothing(ext.useall_argument("@useall (A, B"))
                # Only the last name of a qualified macro name counts.
                @test ext.useall_argument("@Main.useall.usepublic Lin") == "Lin"
                @test isnothing(ext.useall_argument("@useall.x A"))
                @test isnothing(ext.useall_argument("printl"))
                # Installation waits for the REPL interface, also if the frontend yields before it creates it.
                repl = REPL.LineEditREPL(REPL.Terminals.TTYTerminal("dumb", IOBuffer(), IOBuffer(), IOBuffer()), false)
                repl.history_file = false
                task = schedule(Task(() -> ext.await_interface(repl)))
                sleep(0.3)
                @test !istaskdone(task)
                repl.interface = REPL.setup_interface(repl)
                wait(task)
                @test any(m -> m isa LineEdit.Prompt && m.complete isa ext.UseAllCompletionProvider, repl.interface.modes)
                # Other input is completed by Julia's own provider.
                for input in ("printl", "Base.Ite", "@time printl", "\"@useall Lin")
                    @test _complete(input) == _complete(input; native=true)
                end
                @test isnothing(ext.useall_argument("@useall A\nB"))
                @test isnothing(ext.useall_argument("@useall(A) B"))
                @test ext.useall_argument("@useall ") == ""
                @test isnothing(ext.useall_argument("@useall"))
                @test isnothing(ext.useall_argument("@useallx A"))
                @test isnothing(ext.useall_argument("@useall A("))
                @test "println" in _test_completions("printl")  # normal completion unaffected
            finally
                pop!(LOAD_PATH)
            end
        end
    end

    @testset "Aqua" begin
        Aqua.test_all(UseAll)
    end
end
