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
const no_longer_defined = NoLongerDefined()
function Base.show(io::IO, ::MIME"text/plain", v::NoLongerDefined)
    Base.show(io, v)
end
function Base.show(io::IO, ::NoLongerDefined)
    print(io, "<no longer defined>")
end

function _fast_deinit_()
    unregister_auto(quiet=true)
end


end
