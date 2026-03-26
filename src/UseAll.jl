module UseAll

export @useall

# Use `@useall MyPackage` to simplify debugging from the command line.
# TODO: It would be cool if this could register in Revise.jl such that if a symbol is added to the package, revise would also make it automatically available.
macro useall(exs...)
    isempty(exs) && throw(ArgumentError("@useall requires at least one module name, e.g. `@useall MyPackage`"))
    stmts = Expr[]
    for ex in exs
        # Only run `using` for top-level packages; submodules (e.g. Base.Iterators) are already loaded.
        ex isa Symbol && @eval __module__ using $ex
        m = @eval __module__ $ex
        modpath = Expr(:., _splitmodpath(ex)...)
        push!(stmts, Expr(:using, Expr(:(:), modpath, usefulnames(m, __module__)...)))
    end
    Expr(:escape, Expr(:block, stmts...))
end

# Convert a module expression to path components: :Foo → (:Foo,), :(Base.Iterators) → (:Base, :Iterators)
_splitmodpath(s::Symbol) = (s,)
_splitmodpath(ex::Expr) = (_splitmodpath(ex.args[1])..., ex.args[2].value)

function usefulnames(m_from::Module, m_into::Module=Main)
    # Use FQN for `Base.names` to also work if there is a global variable `names` defined in `Main`.
    names(m) = Base.names(m; all=true, imported=true, (@static VERSION >= v"1.12" ? (; usings=true) : (;))...)

    # Skip identifiers already in m_into and hidden names (starting with '#').
    # This excludes module-specific methods `eval`/`include` due to their common function name in m_from and m_into.
    return (Expr(:., s) for s in setdiff(m_from |> names, m_into |> names) if !startswith(s |> string, '#'))
end

end
