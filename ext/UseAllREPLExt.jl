"""
Provides tab-completion for `@useall` arguments (packages and submodules),
reusing the REPL's built-in `using` completion logic.
"""
module UseAllREPLExt

import UseAll
import REPL
import REPL: LineEdit
import REPL.REPLCompletions

# Wrapper around the original provider that intercepts @useall completion.
struct UseAllCompletionProvider <: LineEdit.CompletionProvider
    wrapped::REPL.REPLCompletionProvider
end

REPL.setmodifiers!(cp::UseAllCompletionProvider, m::LineEdit.Modifiers) = REPL.setmodifiers!(cp.wrapped, m)

function LineEdit.complete_line(cp::UseAllCompletionProvider, s::LineEdit.PromptState, mod::Module; hint::Bool=false)
    # Guard against REPL API changes — silently fall back to default completion.
    try
        full = LineEdit.input_string(s)
        pos = thisind(full, position(s))

        # Rewrite "@useall <arg>" → "using <arg>" so the REPL's import completion kicks in.
        m = match(r"@useall\s+((?:\S+\s+)*)(\S*)$", SubString(full, 1, pos))
        if isnothing(m)
            query, query_pos, offset = full, pos, 0
        else
            arg = m[2]
            query = "using $arg"
            query_pos = ncodeunits(query)
            offset = pos - ncodeunits(arg) - ncodeunits("using ")
        end

        ret, query_range, should_complete = REPLCompletions.completions(query, query_pos, mod, cp.wrapped.modifiers.shift, hint)
        range = REPL.to_region(full, (first(query_range) + offset):(last(query_range) + offset))
        cp.wrapped.modifiers = LineEdit.Modifiers()
        return unique!(LineEdit.NamedCompletion[REPLCompletions.named_completion(x) for x in ret]), range, should_complete
    catch
        return REPL.complete_line(cp.wrapped, s, mod; hint)
    end
end

function __init__()
    # In non-interactive mode (e.g. scripts, tests), REPL is loaded but no active_repl exists.
    isdefined(Base, :active_repl) || return
    # Guard against REPL internals changing — silently skip installation.
    try
        repl = Base.active_repl::REPL.LineEditREPL
        for mode in repl.interface.modes
            if mode isa LineEdit.Prompt && mode.complete isa REPL.REPLCompletionProvider
                mode.complete = UseAllCompletionProvider(mode.complete)
            end
        end
    catch
    end
end

end
