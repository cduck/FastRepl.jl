"""
Macros to make the Julia REPL more dynamic and improve developer productivity

See the documentation for ``@repl``.

# FastRepl Development
Use it on itself:
```julia
module _FastRepl using FastRepl end
_FastRepl.FastRepl.@repl using FastRepl; register_auto()
```
"""
module FastRepl

import Base.show

export @repl, @reset, register_auto, unregister_auto


include("register.jl")
include("macros.jl")


struct NoLongerDefined end
no_longer_defined = NoLongerDefined()
show(io::IO, ::MIME"text/plain", v::FastRepl.NoLongerDefined) = show(io, v)
function show(io::IO, ::MIME"text/plain", ::FastRepl.NoLongerDefined)
    print(io, "no_longer_defined")
end

# For debugging
macro dump(expr)
    dump(expr)
end
Base.eval(Main, :(var"@䷀dump" = $var"@dump"))

function _fast_deinit_()
    unregister_auto(quiet=true)
end


end
