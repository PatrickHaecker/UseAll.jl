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

# Julia 1.11 added the `hint` keyword. Julia 1.12 replaced the returned strings and partial string by
# `NamedCompletion`s and a region.
const HAS_HINT = hasmethod(LineEdit.complete_line, Tuple{REPL.REPLCompletionProvider, LineEdit.PromptState, Module}, (:hint,))
const HAS_NAMED_COMPLETION = isdefined(LineEdit, :NamedCompletion)

function install_provider()
    # Only install if the REPL API we depend on for fallback actually exists.
    hasmethod(LineEdit.complete_line, Tuple{REPL.REPLCompletionProvider, LineEdit.PromptState, Module}) || return
    repl = Base.active_repl::REPL.LineEditREPL
    for mode in repl.interface.modes
        if mode isa LineEdit.Prompt && mode.complete isa REPL.REPLCompletionProvider
            mode.complete = UseAllCompletionProvider(mode.complete)
        end
    end
end

function LineEdit.complete_line(cp::UseAllCompletionProvider, s::LineEdit.PromptState, mod::Module; hint::Bool=false)
    # Guard against REPL API changes — silently fall back to default completion.
    try
        full = LineEdit.input_string(s)
        pos = thisind(full, position(s))

        # Rewrite "@useall <arg>" → "using <arg>" so the REPL's import completion kicks in.
        m = match(r"@use(?:all|public)\s+((?:\S+\s+)*)(\S*)$", SubString(full, 1, pos))
        if isnothing(m)
            query, query_pos, offset = full, pos, 0
        else
            arg = m[2]
            query = "using $arg"
            query_pos = ncodeunits(query)
            offset = pos - ncodeunits(arg) - ncodeunits("using ")
        end

        shift = cp.wrapped.modifiers.shift
        ret, query_range, should_complete = @static if HAS_HINT
            REPLCompletions.completions(query, query_pos, mod, shift, hint)
        else
            REPLCompletions.completions(query, query_pos, mod, shift)
        end
        cp.wrapped.modifiers = LineEdit.Modifiers()
        @static if HAS_NAMED_COMPLETION
            range = REPL.to_region(full, (first(query_range) + offset):(last(query_range) + offset))
            return unique!(LineEdit.NamedCompletion[REPLCompletions.named_completion(x) for x in ret]), range, should_complete
        else
            # The partial string is the text before the cursor that the completion replaces.
            return unique!(map(REPLCompletions.completion_text, ret)), query[query_range], should_complete
        end
    catch
        @static if HAS_HINT
            return LineEdit.complete_line(cp.wrapped, s, mod; hint)
        else
            return LineEdit.complete_line(cp.wrapped, s, mod)
        end
    end
end

function __init__()
    if isdefined(Base, :active_repl)
        # Loaded interactively (e.g. `using UseAll` at the REPL or in an `atreplinit` hook).
        schedule_install(Base.active_repl)
    elseif isinteractive()
        # Loaded from startup.jl — the REPL does not exist yet.
        atreplinit(schedule_install)
    end
end

"""
    schedule_install(repl)

Install the `@useall` completion provider into `repl`, or schedule the installation if `repl` has no `interface` yet.

Do nothing unless `repl` is a `REPL.LineEditREPL`, because only that REPL type has completion providers. The REPL
creates its `interface` in the frontend task, after the `atreplinit` hooks have run.
"""
function schedule_install(@nospecialize(repl))
    repl isa REPL.LineEditREPL || return
    if isdefined(repl, :interface)
        try install_provider() catch end
    else
        schedule(Task(await_interface))
    end
    return
end

"""
    await_interface()

Yield until `Base.active_repl` has an `interface`, then install the `@useall` completion provider.

Give up after one second. The frontend task creates the `interface` without yielding, so one `yield` usually
suffices. The limit keeps the loop from spinning forever if the frontend fails before it creates the `interface`.
"""
function await_interface()
    repl = Base.active_repl::REPL.LineEditREPL
    deadline = time_ns() + 1_000_000_000
    while !isdefined(repl, :interface)
        time_ns() < deadline || return
        yield()
    end
    try install_provider() catch end
    return
end

# Named functions instead of closures, so that the REPL start compiles nothing.
precompile(schedule_install, (Any,))
precompile(await_interface, ())

end
