module FastRepl

export @!, @reset!


"""
Make the decorated function or struct redefinable in a REPL.

- Function: Decorate the first method with `@reset` or `@!reset` and the rest
    with `@repl` or `@!`.
- Struct: Decorate the definition with `@repl` or `@!`.
"""
macro repl(expr)
    if is_function_expr(expr)
        _macro_repl_function(expr)
    elseif typeof(expr) <: Expr && expr.head == :struct
        _macro_reset_struct(expr)
    else
        println("Warning: Unsupported argument to @repl")
        expr
    end
end
var"@!" = var"@repl"  # Alias

"""
Define the decorated function or struct from a fresh state.

- Symbol: Clear any previously defined function or symbol.
- Function: Clear any previously defined methods.
- Struct: Decorate the definition with `@reset` or `@!reset`.
"""
macro reset(expr)
    if typeof(expr) <: Symbol
        _macro_reset_symbol(expr)
    elseif is_function_expr(expr)
        _macro_reset_function(expr)
    elseif typeof(expr) <: Expr && expr.head == :struct
        _macro_reset_struct(expr)
    else
        println("Warning: Unsupported argument to @reset")
        expr
    end
end
var"@reset!" = var"@reset"  # Alias

function is_function_expr(expr::Expr)
    (expr.head == :function
        || (expr.head == :(=) && expr.args[1].head == :call)
    )
end

function function_symbol(expr::Expr)
    @assert is_function_expr(expr)
    if typeof(expr.args[1]) <: Symbol
        expr.args[1]
    else  # type is Expr
        @assert expr.args[1].head == :call
        expr.args[1].args[1]
    end
end

function renamed_function(expr::Expr, sym)
    @assert is_function_expr(expr)
    if typeof(expr.args[1]) <: Symbol
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
        i = (
            if haskey(_repl_function_counters, sym)
                _repl_function_counters[sym]
            else
                _repl_function_counters[sym] = 1
            end
        )
        tmp_sym = Symbol("$(sym)䷀v$(i)")
    end
    new_expr = renamed_function(expr, tmp_sym)
    esc(quote
        $new_expr
        $sym = $tmp_sym
    end)
end

"""
Helper for `@reset function ...`.
"""
function _macro_reset_function(expr::Expr)
    sym = function_symbol(expr)
    delete!(_repl_struct_sym_map, sym)
    if haskey(_repl_function_counters, sym)
        _repl_function_counters[sym] += 1
    else
        _repl_function_counters[sym] = 1
    end
    _macro_repl_function(expr)
end

"""
Helper for `@reset function_name`.
"""
function _macro_reset_symbol(sym::Symbol)
    delete!(_repl_struct_sym_map, sym)
    if haskey(_repl_function_counters, sym)
        _repl_function_counters[sym] += 1
    else
        _repl_function_counters[sym] = 1
    end
    esc(quote
        $sym = nothing
    end)
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
    i = (
        if haskey(_repl_function_counters, sym)
            _repl_function_counters[sym] += 1
        else
            _repl_function_counters[sym] = 1
        end
    )
    mod_sym = Symbol("$(sym)䷀v$(i)")
    tmp_sym = :($mod_sym.$sym)
    println(tmp_sym)
    _repl_struct_sym_map[sym] = tmp_sym
    esc(make_top_level(quote
        module $mod_sym
            $expr
        end
        $sym = $mod_sym.$sym
    end))
end


end
