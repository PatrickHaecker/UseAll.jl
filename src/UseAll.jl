module UseAll

export @useall

# Use `@useall MyPackage` to simplify debugging from the command line.
# TODO: It would be cool if this could register in Revise.jl such that if a symbol is added to the package, revise would also make it automatically available.
# TODO: Implement support for a module which is not itself a package, e.g. Base.Iterators
macro useall(exs...)
    isempty(exs) && throw(ArgumentError("@useall requires at least one module name, e.g. `@useall MyPackage`"))
    stmts = Expr[]
    for ex in exs
        @eval __module__ using $ex
        m = @eval __module__ $ex
        push!(stmts, Expr(:using, Expr(:(:), Expr(:., ex), usefulnames(m, __module__)...)))
    end
    Expr(:escape, Expr(:block, stmts...))
end

function usefulnames(m_from::Module, m_into::Module=Main)
    # Use FQN for `Base.names` to also work if there is a global variable `names` defined in `Main`.
    names(m) = Base.names(m; all=true, imported=true, (@static VERSION >= v"1.12" ? (; usings=true) : (;))...)

    # Do not pull in redundant identifiers, as this blocks future reuse of the identifiers without any benefit.
    # Neither import hidden identifier nor the module-specific eval/include.
    return (Expr(:., s) for s in setdiff(m_from |> names, m_into |> names) if !startswith(s |> string, '#') && s ∉ (:eval, :include))
end

end
