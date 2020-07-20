using Base.Meta: isexpr

module _Empty end
_default_names = Set(names(_Empty, all=true))


"""
    @repl import ...
    @repl using ...
    @repl [flag] function ... end
    @repl struct ... end
    @repl [flag] begin ... end

    # In an IJulia cell
    @@repl [flag]
    ...

Make the decorated function or struct redefinable in a REPL.

- Import/using: Decorate a statement with `@repl` to import a fresh version of
    the package under development every time.  `_fast_deinit_` will be called on
    the top module before a re-import if it exists.
- Function: Decorate the first method with `@reset` and the rest with `@repl`.
- Struct: Decorate the definition with `@repl`.
- Block: Apply the `@repl` macro to the top-level of an entire block of code in
    a REPL like Jupyter.

Flags:
- reset: Applies `@reset` to the first method of each function in the block (if
    not a constructor function).
"""
macro repl(expr)
    esc(_macro_repl(expr, __module__))
end
macro repl(flag::Symbol, expr)
    esc(_macro_repl(expr, __module__, [flag]))
end
function _macro_repl(expr, mod, flags=Symbol[])
    if is_function_expr(expr)
        _macro_repl_function(expr, mod)
    elseif isexpr(expr, :struct)
        _macro_repl_struct(expr, mod)
    elseif expr isa Expr && expr.head in (:block, :toplevel)
        _macro_repl_block(expr, mod, flags)
    elseif is_import_expr(expr)
        _macro_repl_import(expr, mod)
    elseif expr === nothing
        nothing
    else
        println("Warning: Unsupported argument to @repl.  $(expr)")
        expr
    end
end

"""
    @reset function ... end

Define the decorated function or struct from a fresh state.

- Symbol: Clear a previously defined function or struct.
- Function: Clear all previously defined methods.
"""
macro reset(expr)
    if expr isa Symbol
        esc(_macro_reset_symbol(expr))
    elseif is_function_expr(expr)
        esc(_macro_reset_function(expr, __module__))
    elseif expr === nothing
        nothing
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
    else
        @assert isexpr(expr.args[1], :call)
        expr.args[1].args[1]
    end
end

function function_with_symbol(expr::Expr, sym)
    @assert is_function_expr(expr)
    if expr.args[1] isa Symbol
        Expr(expr.head, sym, expr.args[2:end]...)
    else
        @assert isexpr(expr.args[1], :call)
        Expr(expr.head,
             Expr(expr.args[1].head, sym, expr.args[1].args[2:end]...),
             expr.args[2:end]...)
    end
end

"""
Helper for `@repl function ...`.
"""
function _macro_repl_function(expr::Expr, mod::Module; nofail::Bool=false,
                              reset::Bool=false)
    @assert is_function_expr(expr)
    quote
        # Defer to runtime
        $_do_temporary_function($(Core.Box(expr)), $mod, $nofail, $reset)
    end
end

_temp_function_symbol(sym, i) = Symbol("䷀$(sym)_v$(i)")

function _do_temporary_function(expr_box, mod, nofail, reset)
    expr = expr_box.contents
    sym = function_symbol(expr)
    out_expr = make_top_level!(quote end)
    counters = actual_getproperty(mod, :䷀function_counters, Dict{Symbol, Int}())
    i = get!(counters, sym, 0)
    if reset || i < 1
        i = counters[sym] += 1
    end
    push!(out_expr.args, :(䷀function_counters = $counters))
    tmp_sym = _temp_function_symbol(sym, i)
    new_expr = function_with_symbol(expr, tmp_sym)

    fallback = true
    try
        Base.eval(mod, :($sym = $no_longer_defined))
        fallback = false
    catch e
        e isa ErrorException || rethrow()
        println("$(nofail ? "Info" : "Warning"): $(sym) is not "
                   * "resettable.")
    end
    if fallback
        push!(out_expr.args, expr)
    else
        push!(out_expr.args, new_expr)
        push!(out_expr.args, :($sym = $tmp_sym))
    end
    Base.eval(mod, out_expr)  # Returns the defined function
end

"""
Helper for `@reset function ...`.
"""
function _macro_reset_function(expr::Expr, mod::Module; nofail::Bool=false)
    _macro_repl_function(expr, mod, nofail=nofail, reset=true)
end

"""
Helper for `@reset function_name`.
"""
function _macro_reset_symbol(sym::Symbol)
    sym_box = Core.Box(sym)
    quote
        ($setindex!)(䷀function_counters,
                     ($get)(䷀function_counters, $sym_box.contents, 0)
                     + ($sym !== $no_longer_defined),
                     $sym_box.contents)
        $sym = $no_longer_defined
        nothing
    end
end

function make_top_level!(expr::Expr)
    if isexpr(expr, :block)
        expr.head = :toplevel
        expr
    else
        expr = quote $expr end
        @assert isexpr(expr, :block)
        expr.head = :toplevel
        expr
    end
end

function struct_name(expr::Expr)::Symbol
    @assert isexpr(expr, :struct)
    expr.args[2] isa Symbol && return expr.args[2]
    root_expr = _first_root_expr(expr.args[2])
    root_expr.args[1]
end

function struct_with_name(expr::Expr, sym::Symbol)
    @assert isexpr(expr, :struct)
    if expr.args[2] isa Symbol
        Expr(expr.head, expr.args[1], sym, expr.args[3:end]...)
    else
        root_expr = _first_root_expr(expr.args[2])
        _with_first_root_expr(
            expr.args[2],
            Expr(root_expr.head, sym, root_expr.args[2:end]...))
    end
end

function expr_with_vals_replaced(expr, old_val, new_val)
    expr == old_val && return new_val
    expr isa Expr || return expr
    new_args = [expr_with_vals_replaced(a, old_val, new_val)
                for a in expr.args]
    Expr(expr.head, new_args...)
end

"""
Helper for `@repl struct ...`.
"""
function _macro_repl_struct(expr::Expr, mod::Module)
    @assert isexpr(expr, :struct)
    quote
        # Defer to runtime
        $_do_temporary_struct($(Core.Box(expr)), $mod)
    end
end

function _do_temporary_struct(expr_box, mod)
    expr = expr_box.contents
    sym = struct_name(expr)
    out_expr = make_top_level!(quote end)
    counters = actual_getproperty(mod, :䷀function_counters, Dict{Symbol, Int}())
    i = counters[sym] = get!(counters, sym, 0) + 1
    push!(out_expr.args, :(䷀function_counters = $counters))
    tmp_sym = _temp_function_symbol(sym, i)
    new_expr = expr_with_vals_replaced(expr, sym, tmp_sym)

    fallback = true
    try
        Base.eval(mod, :($sym = $no_longer_defined))
        fallback = false
    catch e
        e isa ErrorException || rethrow()
        println("Warning: $(sym) is not resettable.")
    end
    if fallback
        push!(out_expr.args, expr)
    else
        push!(out_expr.args, new_expr)
        push!(out_expr.args, :($sym = $tmp_sym))
    end
    Base.eval(mod, out_expr)  # Returns the defined function
end

"""
Helper for `@repl begin ...` and `@@repl ...`.
"""
function _macro_repl_block(expr::Expr, mod::Module, flags=Symbol::[])
    reset_flag = :reset in flags
    known_flags = [:reset]
    if !all(f in known_flags for f in flags)
        unknown = setdiff(flags, known_flags)
        print("Warning: Unknown flag(s) to @@repl: [$(join(unknown, ", "))]")
    end
    if expr isa Expr && expr.head in (:block, :toplevel)
        # A block of statements
        was_defined = Set()
        for i in axes(expr.args, 1)
            sub_expr = expr.args[i]
            if isexpr(sub_expr, :struct)
                sym = struct_name(sub_expr)
                if sym in was_defined
                    println(
                        "Warning: Function definition for $(sym) overwritten "
                        * "by a later struct definition.")
                end
                expr.args[i] = _macro_repl_struct(sub_expr, mod)
                push!(was_defined, sym)
            elseif is_function_expr(sub_expr)
                sym = function_symbol(sub_expr)
                if reset_flag && !(sym in was_defined)
                    expr.args[i] = _macro_reset_function(sub_expr, mod,
                                                         nofail=true)
                else
                    expr.args[i] = _macro_repl_function(sub_expr, mod,
                                                        nofail=true)
                end
                push!(was_defined, sym)
            end
        end
        expr
    else
        # A single statement
        if is_function_expr(expr)
            _macro_repl_function(expr, mod, nofail=true)
        else
            expr
        end
    end
end

function is_import_expr(expr)
    expr isa Expr && expr.head in (:using, :import)
end

function _first_root_expr(expr)
    @assert expr isa Expr
    if length(expr.args) <= 0 || !(expr.args[1] isa Expr)
        expr
    else
        _first_root_expr(expr.args[1])
    end
end

function _with_first_root_expr(expr, new_root_expr)
    @assert expr isa Expr
    if length(expr.args) <= 0 || !(expr.args[1] isa Expr)
        new_root_expr
    else
        Expr(expr.head,
             _with_first_root_expr(expr.args[1], new_root_expr),
             expr.args[2:end]...)
    end
end

function import_expr_package_sym(expr::Expr)
    @assert is_import_expr(expr)
    root_expr = _first_root_expr(expr)
    @assert length(root_expr.args) > 0
    sym = root_expr.args[1]
    @assert sym isa Symbol
    sym
end

function import_expr_package_sym!(expr::Expr, new_vals...)
    @assert is_import_expr(expr)
    root_expr = _first_root_expr(expr)
    @assert length(root_expr.args) > 0
    sym = root_expr.args[1]
    @assert sym isa Symbol
    root_expr.args = [new_vals..., root_expr.args[2:end]...]
    expr
end

function actual_hasproperty(x, s::Symbol)
    try
        getproperty(x, s)
        return true
    catch e
        e isa UndefVarError || rethrow()
        return false
    end
end

function actual_getproperty(x, s::Symbol, default=nothing)
    try
        return getproperty(x, s)
    catch e
        e isa UndefVarError || rethrow()
        return default
    end
end

function _exported_names(mod::Module, imported_mod::Module, ignore=())
    all_names = Set(sym for sym in names(imported_mod, all=true)
                        if actual_hasproperty(mod, sym))
    setdiff!(all_names, _default_names, ignore)
end

"""
Helper for `@repl import ...` and `@repl using ...`.
"""
function _macro_repl_import(expr::Expr, mod::Module)
    sym = import_expr_package_sym(expr)
    sym == :(.) && return expr  # Don't modify relative imports
    pkg_name = string(sym)
    import_expr = import_expr_package_sym!(expr, :(.), :(.), :䷁, sym)
    quote
        $(_do_temporary_import)($pkg_name, $(Core.Box(import_expr)), $mod)
    end
end

function _do_temporary_import(pkg_name, expr_box, mod::Module)
    cleanup_dict = actual_getproperty(mod, :䷀import_variables,
                                      Dict{String, Set{Symbol}}())
    module_dict = actual_getproperty(mod, :䷀import_modules,
                                     Dict{String, Module}())

    # Make temporary module
    scratch = Module(:䷀)
    # Include and import the package in different submodules
    Base.eval(scratch, make_top_level!(quote
        module ䷁
            include(Base.find_package($pkg_name))
        end
        module ䷀S2
            $(expr_box.contents)
        end
    end))
    in_mod = getproperty(scratch.䷁, Symbol(pkg_name))
    out_mod = scratch.䷀S2

    # De-init old module
    old_mod = get(module_dict, pkg_name, nothing)
    module_dict[pkg_name] = in_mod
    if old_mod !== nothing && isdefined(old_mod, :_fast_deinit_)
        try
            old_mod._fast_deinit_()
        catch e
            println(stderr, "Error during fast deinit: $(e)")
            showerror(stderr, e)
        end
    end

    # Assign the correct variables to the imported names
    expr = quote end
    @assert isexpr(expr, :block)
    all_names = _exported_names(out_mod, in_mod, [:䷀S2])
    # Clear old values
    for sym in get(cleanup_dict, pkg_name, Set{Symbol}())
        sym == :䷀S2 && continue  # Skip temporary module name
        assignment = :($sym = $no_longer_defined)
        push!(expr.args, assignment)
    end
    # Save names for later cleanup
    cleanup_dict[pkg_name] = all_names
    # Set new values
    for sym in all_names
        push!(expr.args, :($sym = $out_mod.$sym))
    end
    push!(expr.args, :(䷀import_variables = $cleanup_dict))
    push!(expr.args, :(䷀import_modules = $module_dict))
    Base.eval(mod, expr)
    nothing
end
