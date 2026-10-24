"""
When Revise.jl is loaded, `@useall` registers a callback so that newly added
symbols in a revised module are automatically imported into the caller's scope.
The callback is keyed per (module, target, name selection) to avoid duplicates.
"""
module UseAllReviseExt

import UseAll
import Revise

function UseAll.revise_track(namefn, m::Module, modpath::Expr, into::Module)
    # Full module paths keep callbacks of different modules with the same name apart. A tuple can't collide like a
    # joined string can. A redefined module keeps its path, so its new callback replaces the old one.
    key = (:useall, nameof(namefn), fullname(m), fullname(into))
    # Revise can't track modules without a package or file, like `Main` or modules defined at the REPL. Skip them
    # silently. Report other errors, but keep the import, as the callback is only a convenience.
    try
        Revise.add_callback(String[], [m]; key) do
            for s in UseAll.usefulnames(namefn, m, into)
                Base.eval(into, Expr(:using, Expr(:(:), modpath, s)))
            end
        end
    catch e
        e isa ErrorException && startswith(e.msg, "no Revise.track recipe") && return
        @warn "Revise won't update the names imported from `$m` into `$into`." exception = (e, catch_backtrace())
    end
    return
end

end
