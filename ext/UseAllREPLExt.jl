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

"""
    useall_argument(text) -> Union{String, Nothing}

Return the last, possibly empty, argument of an `@useall` or `@usepublic` call if `text` ends inside that call's
arguments, else `nothing`. Drop spaces after dots, as Julia parses `A. B` like `A.B`.

Use Julia's lexer, so that a macro name in a comment or string doesn't count, and so that incomplete code like
`@useall Base.` works. Accept qualified macro names like `UseAll.@usepublic` and `@UseAll.usepublic`. Only names,
`.`, `,`, `using`, comments, grouping parentheses like in `@useall (A)` and spaces other than newlines may follow
the macro name. Inside parentheses, like in `@useall(A, B)`, newlines also separate arguments. Compare the token
text instead of the token kinds, as the kind names differ between Julia versions.
"""
function useall_argument(text::AbstractString)
    # Skip the lexer for ordinary completion.
    occursin('@', text) || return nothing
    # `:macro` after `@`, `:ident` after a name following `@`, `:name` after the macro name, `:args` inside the
    # arguments, `:code` elsewhere.
    state = :code
    ismacro = false    # Whether the name in `:ident` is `useall` or `usepublic`.
    calldepth = 0      # 1 for a parenthesized call like `@useall(A, B)`, else 0.
    depth = 0          # Open parentheses in the arguments, including the call's.
    closed = false     # Whether a group like `(A)` just closed, so that only a separator may follow.
    afterdot = false   # A space after a dot doesn't end the argument.
    incomment = false  # Whether the last token is a comment.
    arg = IOBuffer()
    code = String(text)
    for token in Base.JuliaSyntax.tokenize(code)
        # Token ranges are byte ranges, so the last byte may lie inside a multibyte character.
        first_byte, last_byte = Int(first(token.range)), Int(last(token.range))
        # Skip the empty error token that follows incomplete code like `Base.`.
        last_byte < first_byte && continue
        t = SubString(code, first_byte, thisind(code, last_byte))
        incomment = startswith(t, '#')
        if state === :ident
            # Only a name that no dot follows is the macro name, as in `@UseAll.useall`.
            if t == "."
                state = :macro
                continue
            end
            state = ismacro ? :name : :code
        end
        if state === :macro
            state = Base.isidentifier(t) ? :ident : :code
            ismacro = t in ("useall", "usepublic")
        elseif state === :name && (isinlinespace(t) || t == "(")
            # The first argument needs a space or `(` before it, otherwise the macro name itself is being completed.
            state = :args
            calldepth = depth = Int(t == "(")
            closed = afterdot = false
            take!(arg)
        elseif state === :args && (incomment || (depth > 0 ? isspacetoken(t) : isinlinespace(t)))
            afterdot || take!(arg)
            closed = false
        elseif state === :args && t == "," && depth == calldepth
            # A comma in grouping parentheses makes a tuple, which is no module path.
            take!(arg)
            closed = afterdot = false
        elseif state === :args && t == "(" && !closed && position(arg) == 0
            depth += 1
        elseif state === :args && t == ")" && depth > calldepth
            depth -= 1
            take!(arg)
            closed = true
            afterdot = false
        elseif state === :args && !closed && (t in ("using", ".", "..", "...") || Base.isidentifier(t))
            write(arg, t)
            afterdot = endswith(t, '.')
        else
            state = t == "@" ? :macro : :code
        end
    end
    return state === :args && !closed && !incomment ? String(take!(arg)) : nothing
end
# Like Julia's lexer, accept any Unicode space and the byte-order mark.
isspacetoken(t) = !isempty(t) && all(c -> isspace(c) || c == '\ufeff', t)
# Outside parentheses, a newline ends the statement.
isinlinespace(t) = isspacetoken(t) && !occursin('\n', t)

completions(query, pos, mod, shift, hint) = @static if HAS_HINT
    REPLCompletions.completions(query, pos, mod, shift, hint)
else
    REPLCompletions.completions(query, pos, mod, shift)
end

isboundmodule(mod, name) = (s = Symbol(name); isdefined(mod, s) && getglobal(mod, s) isa Module)

function install_provider(repl::REPL.LineEditREPL)
    # Only install if the REPL API we depend on for fallback actually exists.
    hasmethod(LineEdit.complete_line, Tuple{REPL.REPLCompletionProvider, LineEdit.PromptState, Module}) || return
    for mode in repl.interface.modes
        if mode isa LineEdit.Prompt && mode.complete isa REPL.REPLCompletionProvider
            mode.complete = UseAllCompletionProvider(mode.complete)
        end
    end
end

function LineEdit.complete_line(cp::UseAllCompletionProvider, s::LineEdit.PromptState, mod::Module; hint::Bool=false)
    # No `try`: the REPL reports errors of Tab completion itself and keeps running.
    result = complete_useall(cp, s, mod, hint)
    isnothing(result) || return result
    @static if HAS_HINT
        return LineEdit.complete_line(cp.wrapped, s, mod; hint)
    else
        return LineEdit.complete_line(cp.wrapped, s, mod)
    end
end

"""
    complete_useall(cp, s, mod, hint)

Complete the module path at the cursor in `s` if it is an argument of `@useall` or `@usepublic`, else return
`nothing`. Rewrite the argument to a `using` statement, so that the REPL's import completion kicks in.
"""
function complete_useall(cp::UseAllCompletionProvider, s::LineEdit.PromptState, mod::Module, hint::Bool)
    full = LineEdit.input_string(s)
    arg = useall_argument(SubString(full, 1, thisind(full, position(s))))
    isnothing(arg) && return nothing
    query = "using " * arg
    # `query` ends with the same last name as the text before the cursor, and the completion region lies in that name.
    # So shift from indices in `query` to indices in `full` by the difference of their lengths.
    offset = position(s) - ncodeunits(query)

    shift = cp.wrapped.modifiers.shift
    ret, query_range, should_complete = completions(query, lastindex(query), mod, shift, hint)
    # The first name may also be a module bound in `mod`, which `using` completion doesn't know. Skip an empty name
    # for hints, as there are too many candidates for a hint anyway.
    if !occursin('.', arg) && !(hint && isempty(arg))
        bound, _, _ = completions(arg, lastindex(arg), mod, shift, hint)
        ret = REPLCompletions.Completion[ret; filter(c -> isboundmodule(mod, REPLCompletions.completion_text(c)), bound)]
    end
    cp.wrapped.modifiers = LineEdit.Modifiers()
    @static if HAS_NAMED_COMPLETION
        range = REPL.to_region(full, (first(query_range) + offset):(last(query_range) + offset))
        named = LineEdit.NamedCompletion[REPLCompletions.named_completion(x) for x in ret]
        return unique!(c -> c.completion, named), range, should_complete
    else
        # The partial string is the text before the cursor that the completion replaces.
        return unique!(map(REPLCompletions.completion_text, ret)), query[query_range], should_complete
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
creates its `interface` in the frontend task, after the `atreplinit` hooks have run. Julia reports errors in
`__init__` and in `atreplinit` hooks, and `errormonitor` reports errors in the scheduled task.
"""
function schedule_install(@nospecialize(repl))
    repl isa REPL.LineEditREPL || return
    if isdefined(repl, :interface)
        install_provider(repl)
    else
        errormonitor(schedule(Task(await_interface)))
    end
    return
end

"""
    await_interface(repl = Base.active_repl)

Wait until `repl` has an `interface`, then install the `@useall` completion provider.

The frontend task of Julia 1.10 to 1.14 creates the `interface` without yielding, so at most one `yield` is needed.
Only if that doesn't suffice, poll every 0.1 s, so that neither a busy machine nor a slow frontend makes the wait spin
or give up early. Warn after about a minute, e.g. if the frontend failed before it created the `interface`.
"""
function await_interface(repl::REPL.LineEditREPL=Base.active_repl::REPL.LineEditREPL)
    for _ in 1:10
        isdefined(repl, :interface) && return install_provider(repl)
        yield()
    end
    for _ in 1:600
        isdefined(repl, :interface) && return install_provider(repl)
        sleep(0.1)
    end
    @warn "The REPL has no interface after a minute, so `@useall` tab completion is unavailable."
    return
end

# Named functions instead of closures, so that the REPL start compiles nothing.
precompile(schedule_install, (Any,))
precompile(await_interface, ())
precompile(await_interface, (REPL.LineEditREPL,))

end
