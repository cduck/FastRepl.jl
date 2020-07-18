# FastRepl.jl

Some macros to work around Julia's inability to delete function methods and redefine structs.

## Example

Clear all previously defined methods with `@reset`:
```julia
@reset function my_function(x)
    x
end

@repl function my_function(x, arg2)
    arg2
end

@repl my_function(x, arg2::Int) = x * arg2
```

Redefine a struct with different memory layout:
```julia
@reset struct MyStruct
    x::Int
end

@repl function MyStruct(x, arg2::Int)
    MyStruct(x * arg2)
end
```
