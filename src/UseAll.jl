module UseAll

export @useall
@static VERSION >= v"1.11" && eval(Expr(:public, Symbol("@usepublic")))

"""
    @useall Module1 [Module2 ...]
    @useall using .SubModule[, .SubModule2 ...]

Import all useful names from the given modules into the caller's module namespace.

Unlike `using Module`, which only imports the explicitly exported names, `@useall` imports
all names — including private and imported ones — except for hidden compiler-generated names
(starting with `#`) and names already present in the target module (such as `eval` and `include`).

Supports top-level packages, submodules, and submodules of the current module:

    @useall TOML Base.Iterators MyModule

Submodules of the caller's module (e.g. defined in `Main`) are detected automatically:
use `@useall MyModule` instead of `@useall .MyModule`, as the latter is invalid syntax in Julia.
This also works for nested paths like `@useall MyModule.Inner` and for other modules bound in the
caller's module, like `@useall Iterators` in `Main`. The first name of a path is looked up in this order:

1. a submodule defined directly in the caller's module,
2. a package (or `Base`, `Core`, `Main`), as in a plain `using` statement,
3. another module bound in the caller's module.

As an alternative to the automatic detection, the `using` syntax is also supported to
explicitly refer to submodules of the current module or its parents. As in a plain `using` statement,
commas separate the paths:

    @useall using .MyModule, ..SiblingModule

When [Revise.jl](https://github.com/timholy/Revise.jl) is loaded, newly exported symbols are
automatically imported after revision.

# Examples
```julia
using UseAll
@useall TOML
@useall TOML Base.Iterators
@useall using .MySubModule
```
"""
macro useall(exs...)
    _useimport(__module__, exs, allnames; macroname="@useall")
end

"""
    UseAll.@usepublic Module1 [Module2 ...]
    UseAll.@usepublic using .SubModule[, .SubModule2 ...]

Import exported and public names from the given modules into the caller's module namespace.

Unlike `@useall`, which imports all names including private ones, `@usepublic` only imports
names that are part of the module's public API: those declared with `export` or (on Julia ≥ 1.11)
the `public` keyword.

`@usepublic` is public but not exported — qualify it as `UseAll.@usepublic` or bring it into
scope with `using UseAll: @usepublic`.

Supports the same syntax as `@useall` — see its documentation for details.

# Examples
```julia
using UseAll
UseAll.@usepublic TOML
UseAll.@usepublic TOML Base.Iterators
UseAll.@usepublic using .MySubModule
```
"""
macro usepublic(exs...)
    _useimport(__module__, exs, publicnames; macroname="@usepublic")
end

function _useimport(__module__::Module, exs, namefn; macroname::String)
    isempty(exs) && throw(ArgumentError("$macroname requires at least one module name, e.g. `$macroname MyPackage`"))
    # `@useall using .A, .B` passes a single `using` Expr; unwrap its args.
    items = length(exs) == 1 && exs[1] isa Expr && exs[1].head === :using ? exs[1].args : exs
    stmts = sizehint!(Expr[], length(items))
    for ex in items
        path = splitmodpath(ex)
        isnothing(path) && throw(ArgumentError("$macroname expects module paths like `MyPackage` or `Base.Iterators`, got `$ex`"))
        m, modpath = resolvemodpath(__module__, path...)
        # `m` may come from a package loaded just now, so query its names in the latest world.
        names = Base.invokelatest(usefulnames, namefn, m, __module__)
        push!(stmts, Expr(:using, Expr(:(:), modpath, names...)))
        revise_track(namefn, m, modpath, __module__)
    end
    Expr(:escape, Expr(:block, stmts...))
end

# No-op by default; overridden by more specific method in UseAllReviseExt.jl when Revise is loaded.
revise_track(_...) = nothing

# True when `name` is a submodule defined directly inside `mod`.
issubmod(mod, name) = name isa Symbol && isdefined(mod, name) && (m = getfield(mod, name)) isa Module && parentmodule(m) === mod

# True when `name` is bound to a module in `mod`, e.g. `Iterators` through `using Base`.
islocalmodule(mod, name) = isdefined(mod, name) && getfield(mod, name) isa Module

# Split a module path into its number of leading dots and its names, or return `nothing` for other expressions:
# `:A` → `(0, [:A])`, `:(A.B)` → `(0, [:A, :B])`, and `..A.B` from the `using` form → `(2, [:A, :B])`.
splitmodpath(s::Symbol) = (0, [s])
function splitmodpath(ex::Expr)
    ex.head === :. || return nothing
    names = Symbol[]
    if all(a -> a isa Symbol, ex.args)
        # Path from the `using` form, e.g. `using ..A.B` stores `..A.B` as `Expr(:., :., :., :A, :B)`.
        ndots = something(findfirst(a -> a !== :., ex.args), length(ex.args) + 1) - 1
        append!(names, @view ex.args[(ndots + 1):end])
        all(a -> a !== :., names) || return nothing
    else
        # Macro argument, e.g. `A.B.C` is `Expr(:., Expr(:., :A, QuoteNode(:B)), QuoteNode(:C))`.
        ndots = 0
        while ex isa Expr && ex.head === :. && length(ex.args) == 2 && ex.args[2] isa QuoteNode
            name = ex.args[2].value
            name isa Symbol || return nothing
            pushfirst!(names, name)
            ex = ex.args[1]
        end
        ex isa Symbol || return nothing
        pushfirst!(names, ex)
    end
    isempty(names) && return nothing
    return ndots, names
end
splitmodpath(_) = nothing

# Find the module for a path and the path for the generated `using` statement.
# Relative paths start at the caller. For absolute paths, the first name is looked up in this order:
# 1. a submodule defined directly in the caller,
# 2. a package (or `Base`, `Core`, `Main`), as in a plain `using` statement,
# 3. another module bound in the caller, e.g. `Iterators`.
function resolvemodpath(caller::Module, ndots::Int, names::Vector{Symbol})
    root = first(names)
    if ndots == 0
        if !issubmod(caller, root) && (root in (:Base, :Core, :Main) ||
                                       !isnothing(Base.identify_package(caller, String(root))) ||
                                       !islocalmodule(caller, root))
            # `Base.require` throws the usual "package not found" error if `root` is no package either.
            rootmod = root === :Base ? Base : root === :Core ? Core : root === :Main ? Main : Base.require(caller, root)
            return getpath(rootmod, @view names[2:end]), Expr(:., names...)
        end
        ndots = 1
    end
    base = caller
    for _ in 2:ndots
        base = parentmodule(base)
    end
    return getpath(base, names), Expr(:., fill(:., ndots)..., names...)
end

# Follow `names` from `m`. Use the latest world, because `m` may belong to a package loaded just now.
getpath(m::Module, names) = foldl((m, name) -> Base.invokelatest(getglobal, m, name)::Module, names; init=m)

# All names in a module, including private, imported, and (on Julia ≥ 1.12) usings.
allnames(m::Module) = Base.names(m; all=true, imported=true, (@static VERSION >= v"1.12" ? (; usings=true) : (;))...)

# Exported and public names (Julia ≥ 1.11 includes `public`-declared names).
publicnames(m::Module) = Base.names(m)

# Skip identifiers already in m_into and hidden names (starting with '#').
# This excludes module-specific methods `eval`/`include` due to their common function name in m_from and m_into.
usefulnames(namefn, m_from::Module, m_into::Module=Main) =
    (Expr(:., s) for s in setdiff(namefn(m_from), allnames(m_into)) if !startswith(s |> string, '#'))
usefulnames(m_from::Module, m_into::Module=Main) = usefulnames(allnames, m_from, m_into)

const REPL_PKGID = Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL")

# Since Julia 1.11, Base loads the running REPL through `Base.require_stdlib`, which does not register it in
# `Base.loaded_modules`. Package extensions loaded afterwards therefore do not see REPL as loaded, so
# `UseAllREPLExt` would not load. Register REPL regularly when a REPL is running.
function __init__()
    isdefined(Base, :active_repl) || return
    Base.root_module_exists(REPL_PKGID) || Base.require(REPL_PKGID)
    return
end

end
