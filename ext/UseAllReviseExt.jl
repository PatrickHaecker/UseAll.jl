"""
When Revise.jl is loaded, `@useall` registers a callback so that newly added
symbols in a revised module are automatically imported into the caller's scope.
The callback is keyed per (module, target) pair to avoid duplicates.
"""
module UseAllReviseExt

import UseAll
import Revise

function UseAll.revise_track(m::Module, modpath::Expr, into::Module)
    # Revise can't track all modules (e.g. Base submodules) and as we are using private API here,
    # this could fail in the future, so we silently catch any errors to avoid breaking the user's session.
    try
        Revise.add_callback(String[], [m]; key=Symbol(:useall_, nameof(m), :_, nameof(into))) do
            for s in UseAll.usefulnames(m, into)
                Base.eval(into, Expr(:using, Expr(:(:), modpath, s)))
            end
        end
    catch
    end
end

end
