# Changelog

## v0.1.4

- Module paths are now resolved in a fixed order: a submodule of the current module, then a
  package (including `Base`, `Core` and `Main`), then any other module bound in the current
  module. This adds support for nested submodules (`@useall MyModule.Inner`) and bound
  modules (`@useall Iterators`).
  **Note:** in a module other than `Main` that has its own submodule `A`, `@useall A.B` now
  uses that submodule. Previously it used a package `A` loaded in `Main`.
- Fixed `@useall using ..SiblingModule` and other relative paths with more than one dot.
- Fixed `@useall Pkg.Sub` when `Pkg` is not loaded into `Main`. Packages are now loaded
  without an extra `using Pkg` in the calling module.
- Invalid arguments now throw an `ArgumentError` with a clear message.
- Revise.jl: callbacks for modules with the same name in different parents, and for
  `@useall` and `@usepublic` on the same module, no longer replace each other.
- The Revise and REPL extensions now report unexpected errors instead of hiding them.
- REPL: the extension now also loads when `REPL` is loaded after `UseAll` (e.g. from
  `startup.jl`), installs its completion provider without polling with `sleep` or compiling at
  REPL start, and supports tab completion on Julia 1.10 and 1.11.
- REPL: tab completion now works for code after `@useall …;` or a newline, and handles
  non-ASCII characters before the cursor correctly. It uses Julia's lexer, so `@useall` in
  comments and strings no longer triggers it, and it also completes modules bound in the
  current module, such as modules defined at the REPL.
- REPL: tab completion now also works for qualified and parenthesized macro calls
  (`@UseAll.useall X`, `@useall(X`, `UseAll.@usepublic(X`), after comments and grouping
  parentheses in the arguments, and after a space following a dot (`@useall MyModule. In`).
- Removed the template tests and the `TestItemRunner` test dependency.

## v0.1.3

- Added `@usepublic` macro (public, not exported): like `@useall` but imports only exported
  and public names. Includes REPL tab completion and Revise.jl support.

## v0.1.2

- Added support for the `@useall using .SubModule` syntax as an alternative way to
  explicitly refer to submodules of the current module. This mirrors the syntax
  supported by Reexport.jl and works around `.SubModule` being illegal syntax
  in Julia macro arguments.

## v0.1.1

- Added support for submodules of the current module. `@useall MyModule` now works when
  `MyModule` is defined inside the caller's module (e.g. at the REPL), without requiring
  a `.MyModule` prefix (which is invalid Julia syntax in macro arguments).

## v0.1.0

- Initial release.
- `@useall` macro for importing all useful names from packages and submodules.
- Revise.jl integration: newly exported symbols are auto-imported after revision.
- REPL integration: tab completion for `@useall` arguments.
