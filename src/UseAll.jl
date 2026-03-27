module UseAll

export @useall

"""
    @useall Module1 [Module2 ...]

Import all useful names from the given modules into the caller's module namespace.

Unlike `using Module`, which only imports the explicitly exported names, `@useall` imports
all names — including private and imported ones — except for hidden compiler-generated names
(starting with `#`) and names already present in the target module (such as `eval` and `include`).

Supports top-level packages and submodules:

    @useall TOML Base.Iterators

When [Revise.jl](https://github.com/timholy/Revise.jl) is loaded, newly exported symbols are
automatically imported after revision.

# Examples
```julia
using UseAll
@useall TOML
@useall TOML Base.Iterators
```
"""
macro useall(exs...)
    isempty(exs) && throw(ArgumentError("@useall requires at least one module name, e.g. `@useall MyPackage`"))
    stmts = sizehint!(Expr[], length(exs))
    for ex in exs
        # Only run `using` for top-level packages; submodules (e.g. Base.Iterators) are already loaded.
        ex isa Symbol && @eval __module__ using $ex
        m = @eval __module__ $ex
        modpath = Expr(:., splitmodpath(ex)...)
        push!(stmts, Expr(:using, Expr(:(:), modpath, usefulnames(m, __module__)...)))
        revise_track(m, modpath, __module__)
    end
    Expr(:escape, Expr(:block, stmts...))
end

# No-op by default; overridden by more specific method in UseAllReviseExt.jl when Revise is loaded.
revise_track(_...) = nothing

# Convert a module expression to path components: :Foo → (:Foo,), :(Base.Iterators) → (:Base, :Iterators)
splitmodpath(s::Symbol) = (s,)
splitmodpath(ex::Expr) = (splitmodpath(ex.args[1])..., ex.args[2].value)

# All names in a module, including private, imported, and (on Julia ≥ 1.12) usings.
allnames(m::Module) = Base.names(m; all=true, imported=true, (@static VERSION >= v"1.12" ? (; usings=true) : (;))...)

# Skip identifiers already in m_into and hidden names (starting with '#').
# This excludes module-specific methods `eval`/`include` due to their common function name in m_from and m_into.
usefulnames(m_from::Module, m_into::Module=Main) =
    (Expr(:., s) for s in setdiff(m_from |> allnames, m_into |> allnames) if !startswith(s |> string, '#'))

end
