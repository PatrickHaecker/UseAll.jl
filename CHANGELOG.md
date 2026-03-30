# Changelog

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
