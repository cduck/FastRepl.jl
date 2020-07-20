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
        _macro_repl_function(expr)
    elseif isexpr(expr, :struct)
        _macro_reset_struct(expr)
    elseif expr isa Expr && expr.head in (:block, :toplevel)
        _macro_repl_block(expr, flags)
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
        esc(_macro_reset_function(expr))
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

_repl_function_counters = Dict()
_repl_struct_sym_map = Dict()
"""
Helper for `@repl function ...`.
"""
function _macro_repl_function(expr::Expr; nofail::Bool=false)
    sym = function_symbol(expr)
    if haskey(_repl_struct_sym_map, sym)
        tmp_sym = _repl_struct_sym_map[sym]
    else
        i = get!(_repl_function_counters, sym, 1)
        tmp_sym = Symbol("$(sym)䷀v$(i)")
    end
    new_expr = function_with_symbol(expr, tmp_sym)
    expr_box = Core.Box(expr)
    new_expr_box = Core.Box(new_expr)
    if nofail
        quote
            # Make a private scope to not pollute the user's global namespace
            (() -> begin
                fallback = true
                try
                    global $sym = $no_longer_defined
                    fallback = false
                catch e
                    e isa ErrorException || rethrow()
                    println("Info: $($sym) is not resettable.")
                end
                if fallback
                    eval($expr_box.contents)
                else
                    eval(($make_top_level!)(quote
                        $$new_expr_box.contents
                        global $$sym = $$tmp_sym
                    end))
                end
                $sym
            end)()
        end
    else
        quote
            $new_expr
            $sym = $tmp_sym
        end
    end
end

"""
Helper for `@reset function ...`.
"""
function _macro_reset_function(expr::Expr; nofail::Bool=false)
    sym = function_symbol(expr)
    delete!(_repl_struct_sym_map, sym)
    _repl_function_counters[sym] = get(_repl_function_counters, sym, 0) + 1
    _macro_repl_function(expr, nofail=nofail)
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

"""
Helper for `@repl struct ...` and `@reset struct ...`.
"""
function _macro_reset_struct(expr::Expr)
    @assert isexpr(expr, :struct)
    sym = expr.args[2]
    i = _repl_function_counters[sym] = get(_repl_function_counters, sym, 0) + 1
    mod_sym = Symbol("$(sym)䷀v$(i)")
    tmp_sym = :($mod_sym.$sym)
    _repl_struct_sym_map[sym] = tmp_sym
    make_top_level!(quote
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
                    expr.args[i] = _macro_reset_function(sub_expr, nofail=true)
                else
                    expr.args[i] = _macro_repl_function(sub_expr, nofail=true)
                end
                push!(was_defined, sym)
            end
        end
        expr
    else
        # A single statement
        if is_function_expr(expr)
            _macro_repl_function(expr, nofail=true)
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
