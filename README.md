# UseAll

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://PatrickHaecker.github.io/UseAll.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://PatrickHaecker.github.io/UseAll.jl/dev)
[![Test workflow status](https://github.com/PatrickHaecker/UseAll.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/PatrickHaecker/UseAll.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/PatrickHaecker/UseAll.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/PatrickHaecker/UseAll.jl)
[![Docs workflow Status](https://github.com/PatrickHaecker/UseAll.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/PatrickHaecker/UseAll.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

`UseAll.jl` provides `@useall`, a macro that brings all useful names from one or more modules into the current module.

```julia
using UseAll

@useall TOML Base.Iterators
```

After that, names such as `countfrom` can be used directly, without writing `Base.Iterators.countfrom`.

Submodules of the current module are detected automatically, so if you defined a module at the REPL you can write:

```julia
module MyModule
    f(x) = x + 1
end

@useall MyModule   # The Julia parser does not accept `@useall .MyModule` here.
```

As an alternative (mirroring the syntax supported by Reexport.jl), you can also use the `using` form to explicitly refer to submodules of the current module:

```julia
@useall using .MyModule
```

This is useful while working in the REPL: By pulling names from a package or submodule into `Main`, you can execute copy-pasted code from a module. That means all your previous definitions in your REPL session or from your `startup.jl` remain available. You can also add the names from more than one module and can execute their copy-pasted code without doing anything else in-between.

It is also useful in closely coupled code, for example in a package's own `runtests.jl`, where explicit imports can become noisy and the code intentionally works with many internals of the same package.

## What It Imports

`@useall` imports public and non-public names, including names imported into the source module, while skipping hidden compiler-generated names and names already present in the target module such as `eval` and `include`.

## Why Not Just Use Something Else?

- `import` does not import any binding which is not explicitly listed.
- `using` and `ImportAll.jl` only import the exported bindings.
- `REPL.activate(mod)` changes the evaluation context, but then you are no longer working naturally in `Main`; existing bindings from `Main` are not directly part of that workflow, and it only targets one active module at a time.
- `Reexport.jl` must be set up inside a package by the package author to forward APIs; it is not something you trigger ad hoc from the REPL.

## When Not To Use `UseAll.jl`

Do not use `UseAll.jl` in a regular package. If code side-steps module access boundaries and relies on internals, that usually points to a poor design. `UseAll.jl` is intended for debugging, interactive exploration and deliberately tightly coupled code, not as a general design pattern.

## Package Extensions

`UseAll.jl` ships two optional package extensions:

- `Revise` integration: when `Revise.jl` is loaded, newly added symbols to `MyModule` are brought in automatically into the namespace of your currently active module (typically `Main`) after you did a `@useall MyModule`.
- `REPL` integration: tab completion for `@useall` arguments, reusing Julia's REPL completion behavior for `using`.

Both extensions rely on private Julia or package internals. They are therefore provided on a best-effort basis and are designed to fail silently on Julia versions or environments where the required internals are unavailable or have changed.
