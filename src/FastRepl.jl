module FastRepl

using Base.Meta: isexpr

export @repl, @reset, register_auto


include("register.jl")


"""
    @repl [flag] function ... end
    @repl [flag] struct ... end
    @repl [flag] begin
        ...
    end

    # In an IJulia cell
    @@repl [flag]
    ...

Make the decorated function or struct redefinable in a REPL.

- Function: Decorate the first method with `@reset` and the rest with `@repl`.
- Struct: Decorate the definition with `@repl`.
- Block: Apply the `@repl` macro to the top-level of an entire block of code in
    a REPL like Jupyter.

Flags:
- reset: Applies `@reset` to the first method of each function in the block (if
    not a constructor function).
"""
macro repl(expr)
    esc(_macro_repl(expr))
end
macro repl(flag::Symbol, expr)
    esc(_macro_repl(expr, [flag]))
end
function _macro_repl(expr, flags=Symbol[])
    if is_function_expr(expr)
        _macro_repl_function(expr)
    elseif isexpr(expr, :struct)
        _macro_reset_struct(expr)
    elseif expr isa Expr && expr.head in (:block, :toplevel)
        _macro_repl_block(expr, flags)
    else
        println("Warning: Unsupported argument to @repl.  $(expr)")
        expr
    end
end

"""
Define the decorated function or struct from a fresh state.

- Symbol: Clear any previously defined function or symbol.
- Function: Clear any previously defined methods.
- Struct: Decorate the definition with `@reset`.
"""
macro reset(expr)
    if expr isa Symbol
        esc(_macro_reset_symbol(expr))
    elseif is_function_expr(expr)
        esc(_macro_reset_function(expr))
    elseif isexpr(expr, :struct)
        esc(_macro_reset_struct(expr))
    else
        println("Warning: Unsupported argument to @reset.  $(expr)")
        esc(expr)
    end
end

function is_function_expr(expr)
    (isexpr(expr, :function)
     || isexpr(expr, :macro)
     || (isexpr(expr, :(=)) && isexpr(expr.args[1], :call))
    )
end

function function_symbol(expr::Expr)
    @assert is_function_expr(expr)
    if expr.args[1] isa Symbol
        expr.args[1]
    else  # type is Expr
        @assert expr.args[1].head == :call
        expr.args[1].args[1]
    end
end

function renamed_function(expr::Expr, sym)
    @assert is_function_expr(expr)
    if expr.args[1] isa Symbol
        Expr(expr.head, sym, expr.args[2:end]...)
    else  # type is Expr
        @assert expr.args[1].head == :call
        Expr(:function,
            Expr(expr.args[1].head, sym, expr.args[1].args[2:end]...),
            expr.args[2:end]...)
    end
end

_repl_function_counters = Dict()
_repl_struct_sym_map = Dict()
"""
Helper for `@repl function ...`.
"""
function _macro_repl_function(expr::Expr)
    sym = function_symbol(expr)
    if haskey(_repl_struct_sym_map, sym)
        tmp_sym = _repl_struct_sym_map[sym]
    else
        i = get!(_repl_function_counters, sym, 1)
        tmp_sym = Symbol("$(sym)䷀v$(i)")
    end
    new_expr = renamed_function(expr, tmp_sym)
    quote
        $new_expr
        $sym = $tmp_sym
    end
end

"""
Helper for `@reset function ...`.
"""
function _macro_reset_function(expr::Expr)
    sym = function_symbol(expr)
    delete!(_repl_struct_sym_map, sym)
    _repl_function_counters[sym] = get(_repl_function_counters, sym, 0) + 1
    _macro_repl_function(expr)
end

"""
Helper for `@reset function_name`.
"""
function _macro_reset_symbol(sym::Symbol)
    delete!(_repl_struct_sym_map, sym)
    _repl_function_counters[sym] = get(_repl_function_counters, sym, 0) + 1
    quote
        $sym = nothing
    end
end

function make_top_level(expr::Expr)
    if expr.head == :block
        Expr(:toplevel, expr.args...)
    else
        expr
    end
end

"""
Helper for `@repl struct ...` and `@reset struct ...`.
"""
function _macro_reset_struct(expr::Expr)
    @assert expr.head == :struct
    sym = expr.args[2]
    i = _repl_function_counters[sym] = get(_repl_function_counters, sym, 0) + 1
    mod_sym = Symbol("$(sym)䷀v$(i)")
    tmp_sym = :($mod_sym.$sym)
    println(tmp_sym)
    _repl_struct_sym_map[sym] = tmp_sym
    make_top_level(quote
        module $mod_sym
            $expr
        end
        $sym = $mod_sym.$sym
    end)
end

"""
Helper for `@repl begin ...` and `@@repl ...`.
"""
function _macro_repl_block(expr::Expr, flags=Symbol::[])
    reset_flag = :reset in flags
    known_flags = [:reset]
    if !all(f in known_flags for f in flags)
        unknown = setdiff(flags, known_flags)
        print("Warning: Unknown flag(s) to @@repl: [$(join(unknown, ", "))]")
    end
    if expr isa Expr && expr.head in (:block, :toplevel)
        # A block of statements
        was_defined::Set{Symbol} = Set()
        for i in axes(expr.args, 1)
            sub_expr = expr.args[i]
            if isexpr(sub_expr, :struct)
                sym = sub_expr.args[2]
                expr.args[i] = _macro_reset_struct(sub_expr)
                push!(was_defined, sym)
            elseif is_function_expr(sub_expr)
                sym = function_symbol(sub_expr)
                if reset_flag && !(sym in was_defined)
                    expr.args[i] = _macro_reset_function(sub_expr)
                else
                    expr.args[i] = _macro_repl_function(sub_expr)
                end
                push!(was_defined, sym)
            end
        end
        expr
    else
        # A single statement
        if is_function_expr(expr)
            _macro_repl_function(expr)
        else
            expr
        end
    end
end


end
