"""

See the documentation of ``@repl``.

# Development
Use it on itself:
```julia
module _FastRepl using FastRepl end
_FastRepl.FastRepl.@repl using FastRepl; register_auto()
```
"""
module FastRepl

export @repl, @reset, register_auto, unregister_auto


include("register.jl")
include("macros.jl")


struct NoLongerDefined end
no_longer_defined = NoLongerDefined()

# For debugging
macro dump(expr)
    dump(expr)
end
Base.eval(Main, :(var"@䷀dump" = $var"@dump"))

function _fast_deinit_()
    unregister_auto(quiet=true)
end


end
