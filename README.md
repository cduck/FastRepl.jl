# FastRepl.jl

Some macros to work around Julia's inability to delete function methods and redefine structs.

## Examples

#### Quickly reload a package (useful while developing a package)
```julia
# Running this line again will reload the package
# This can be any (single) valid import or using statement
@repl using MyPackage
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

Some of the above macros can be automatically applied in an IJulia notebook by including the following line in the first cell:
```julia
using FastRepl; register_auto()
```

#### Usage
```julia
### Cell 1 ###
using FastRepl; register_auto()
# Other imports
@repl using MyPackage  # Quikly reimport package

### Cell 2 ###
@@repl reset  # Resets all functions defined in the cell

# The @repl or @reset macros are automatically added
function my_function(x) x end
function my_function(x, arg2) arg2 end

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
