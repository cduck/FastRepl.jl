# FastRepl.jl

Some macros to work around [Julia](https://julialang.org/)'s inability to reload packages, remove function methods, and redefine structs.

## Install

Install FastRepl with Julia's package manager:
```bash
julia -e 'using Pkg; Pkg.add("https://github.com/cduck/FastRepl.jl")'
```

## Examples

#### Quickly reload a package (useful while developing a package)
```julia
# Running this cell again will reload the package
# This can be any (single) valid import or using statement
@reset using MyPackage
@repl import MyPackage: x, y
@repl import MyPackage.z

# When developing a standalone file not in a package:
@repl include("MyFile.jl") using .MyFile
```

#### Clear old methods from a function
```julia
# Create a new function without any previously defined methods
@reset function my_function(x)
    x
end

# Add methods to the function defined above
@repl function my_function(x, arg2)
    arg2
end

@repl my_function(x, arg2::Int) = x * arg2
```

#### Redefine a struct even if it has an incompatible memory layout
```julia
# Define a new struct (any previously defined constructors are cleared)
@repl struct MyStruct
    x::Int
    # An inner constructor
    MyStruct(x) = new(x * 2)
end

# Add a constructor to the struct
@repl function MyStruct(x, arg2::Int)
    MyStruct(x * arg2)
end
```

## IJulia

Some of the above macros can be automatically applied in an [IJulia](https://github.com/JuliaLang/IJulia.jl) notebook by including the following line in the first cell:
```julia
using FastRepl; register_auto()
```

#### Usage
```julia
### Cell 1 ###
using FastRepl; register_auto()
# Other imports
@repl using MyPackage  # Quikly reload package
@repl include("MyFile.jl") using .MyFile  # Quikly reload file
```
```julia
### Cell 2 ###
@@repl reset  # Reset all functions defined in the cell

# The @repl or @reset macros are automatically added
function my_function(x) x end
function my_function(x, arg2) arg2 end
```
```julia
### Cell 3 ###
# In most cases, no code change is needed.
# IJulia automatically applies the macro.

function my_function(x, arg2::Int) = x * arg2

struct MyStruct
    x::Int
    # An inner constructor
    MyStruct(x) = new(x * 2)
end
MyStruct(x, arg2::Int) = MyStruct(x * arg2)
```
