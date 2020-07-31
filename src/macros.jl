using Base.Meta: isexpr


function actual_hasproperty(x, s::Symbol)
    try
        getproperty(x, s)
        return true
    catch e
        e isa UndefVarError || rethrow()
        return false
    end
end

_std_modules = Dict(:Core=>Core, :Base=>Base, :Main=>Main)
module _䷀Empty end
_default_names = Set(names(_䷀Empty, all=true))
for std_mod in values(_std_modules)
    union!(_default_names,
           Set(sym for sym in names(std_mod, all=true, imported=true)
                   if actual_hasproperty(_䷀Empty, sym)))
end


"""
    @repl import ...
    @repl using ...
    @repl include("MyFile.jl")
    @repl include("MyFile.jl") using .MyFile
    @repl [flag] function ... end
    @repl struct ... end
    @repl [flag] begin ... end

    # In an IJulia cell
    @@repl [flag]
    ...

Make the decorated function or struct redefinable in a REPL.

- Import/using: Reload a package.  Decorate the first import for a package with
    `@reset` and later imports with `@repl`.  `_fast_deinit_` will be called on
    the top module before a re-import if it exists.  Do not use when importing
    functions to add methods.
- Include: Run the content of a file.  Any import statements involving any
    modules defined in that file must be included in the same macro call.
- Function: Decorate the first method with `@reset` and the rest with `@repl`.
- Struct: Decorate the definition with `@repl`.
- Block: Apply the `@repl` macro to the top-level of an entire block of code in
    a REPL like Jupyter.

Flags:
- reset: Applies `@reset` to the first method of each function in the block (if
    not a constructor function).

Broken:
- Docstrings on decorated definitions don't work currently.
"""
macro repl(expr)
    esc(_macro_repl(expr, __module__))
end
macro repl(flag::Symbol, expr)
    esc(_macro_repl(expr, __module__, [flag]))
end
macro repl(expr::Expr, expr2, exprs...)
    if is_include_expr(expr)
        _macro_repl_include(__module__, expr, expr2, exprs...)
    else
        println("Error: Unsupported arguments to @repl.  $([expr, exprs...])")
        expr
    end
end
macro repl_reset(expr)
    esc(_macro_repl(expr, __module__, [:reset]))
end
function _macro_repl(expr, mod, flags=Symbol[])
    if is_function_expr(expr)
        _macro_repl_function(expr, mod)
    elseif isexpr(expr, :struct)
        _macro_repl_struct(expr, mod)
    elseif expr isa Expr && expr.head in (:block, :toplevel)
        _macro_repl_block(expr, mod, flags)
    elseif is_import_expr(expr)
        _macro_repl_import(expr, mod; reset=false)
    elseif is_include_expr(expr)
        _macro_repl_include(mod, expr)
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

- Import/using: Reload a package.  Decorate the first import for a package with
    `@reset` and later imports with `@repl`.
- Symbol: Clear a previously defined function or struct.
- Function: Clear all previously defined methods.
"""
macro reset(expr)
    if expr isa Symbol
        esc(_macro_reset_symbol(expr, __module__))
    elseif is_function_expr(expr)
        esc(_macro_reset_function(expr, __module__))
    elseif is_import_expr(expr)
        _macro_repl_import(expr, __module__; reset=true)
    elseif expr === nothing
        nothing
    else
        println("Warning: Unsupported argument to @reset.  $(expr)")
        esc(expr)
    end
end

function is_function_expr(expr)
    isexpr(expr, :function) && return true
    isexpr(expr, :macro) && return true
    if isexpr(expr, :(=))
        sub_expr = expr.args[1]
        while sub_expr isa Expr && sub_expr.head in (:where, :(::), :curly)
            sub_expr = sub_expr.args[1]
        end
        isexpr(sub_expr, :call) && return true
    end
    false
end

function function_symbol(expr::Expr)
    @assert is_function_expr(expr)
    if expr.args[1] isa Symbol
        expr.args[1]
    else
        sub_expr = expr.args[1]
        while (sub_expr isa Expr
                && sub_expr.head in (:where, :(::), :curly, :call))
            sub_expr = sub_expr.args[1]
        end
        sub_expr::Symbol
    end
end

function function_with_symbol(expr::Expr, sym)
    @assert is_function_expr(expr)
    if expr.args[1] isa Symbol
        Expr(expr.head, sym, expr.args[2:end]...)
    else
        decl = copy(expr.args[1])
        sub_expr = decl
        while (sub_expr isa Expr
                && sub_expr.head in (:where, :(::), :curly, :call)
                && sub_expr.args[1] isa Expr)
            sub_expr = sub_expr.args[1] = copy(sub_expr.args[1])
        end
        @assert sub_expr.args[1] isa Symbol
        sub_expr.args[1] = sym
        Expr(expr.head, decl, expr.args[2:end]...)
    end
end

function _get_temp_symbol(mod::Module, sym, increment::Bool=false)
    if isdefined(mod, :䷀symbol_map)
        map = getproperty(mod, :䷀symbol_map)
    else
        map = Base.eval(mod, :(䷀symbol_map = Dict{Any, Any}()))
    end
    if isdefined(mod, :䷀symbol_counters)
        counters = getproperty(mod, :䷀symbol_counters)
    else
        counters = Base.eval(mod, :(䷀symbol_counters = Dict{Any, Int}()))
    end

    if increment || !haskey(map, sym)
        i = get!(counters, sym, 0)
        if increment || i == 0
            i = counters[sym] += 1
        end
        map[sym] = _temp_function_symbol(sym, i)
    else
        map[sym]
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
    tmp_sym = _get_temp_symbol(mod, sym, reset)
    def_sym = tmp_sym
    if isexpr(expr, :macro)
        sym = Symbol("@" * string(sym))
        def_sym = Symbol("@" * string(def_sym))
    end
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
        push!(out_expr.args, :($sym = $def_sym))
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
function _macro_reset_symbol(sym::Symbol, mod::Module)
    sym_box = Core.Box(sym)
    quote
        if isdefined($mod, $sym_box.contents)
            ($_get_temp_symbol)($mod, $sym_box.contents,
                                $sym !== $no_longer_defined)
            $sym = $no_longer_defined
        end
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
        Expr(expr.head,
             expr.args[1],
             _with_first_root_expr(
                expr.args[2],
                Expr(root_expr.head, sym, root_expr.args[2:end]...)),
             expr.args[3:end]...)
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
    tmp_sym = _get_temp_symbol(mod, sym, true)
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
                        "Warning: Definition for $(sym) overwritten by a later "
                        * "struct definition.")
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

function import_expr_package_syms(expr::Expr)
    @assert is_import_expr(expr)
    root_expr = _first_root_expr(expr)
    @assert isexpr(root_expr, :(.))
    @assert length(root_expr.args) > 0
    syms = root_expr.args
    @assert all(sym isa Symbol for sym in syms)
    syms
end

function import_expr_package_syms!(expr::Expr, new_syms...)
    @assert is_import_expr(expr)
    root_expr = _first_root_expr(expr)
    @assert length(root_expr.args) > 0
    sym = root_expr.args[1]
    @assert sym isa Symbol
    root_expr.args = [new_syms...]
    expr
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
    all_names = Set(sym for sym in names(imported_mod, all=true, imported=true)
                        if actual_hasproperty(mod, sym))
    setdiff!(all_names, _default_names, ignore)
end

function actual_all_names(mod, include_default=false, include_hidden=false)
    visible_names = names(mod, all=true, imported=true)
    all_names = Set{Symbol}()
    for sym in visible_names
        name = string(sym)
        if !include_hidden
            name[1] in "#䷀" && continue  # Skip hidden names
        end
        push!(all_names, sym)
        val = getproperty(mod, sym)
        if val isa Module
            for sub_sym in names(val, all=true, imported=true)
                if !include_hidden
                    string(sub_sym)[1] in "#䷀" && continue  # Skip hidden names
                end
                actual_hasproperty(mod, sub_sym) || continue
                push!(all_names, sub_sym)
            end
        end
    end
    if !include_default
        setdiff!(all_names, _default_names)
    end
    all_names
end

"""
Reload a package but don't rebind any names.
"""
function _reload_package(into::Module, pkg_name; force::Bool=true)
    sym = Symbol(pkg_name)
    haskey(_std_modules, sym) && return _std_modules[sym]
    uuidkey = Base.identify_package(into, pkg_name)
    if uuidkey === nothing
        throw(ArgumentError("""
            Package $(pkg_name) not found.
            - Run `import Pkg; Pkg.add($(repr(pkg_name)))` to install the $pkg_name package.
            """))
    end
    if force || !Base.root_module_exists(uuidkey)
        Base._require(uuidkey)  # Force reload
        for callback in Base.package_callbacks
            Base.invokelatest(callback, uuidkey)
        end
    end
    return Base.root_module(uuidkey)
end

"""
Helper for `@repl import ...`, `@repl using ...`, `@reset import/using`.
"""
function _macro_repl_import(expr::Expr, mod::Module; reset::Bool=false,
                            pkg_sym_out=Ref(:(!)),
                            already_reset=Set{Symbol}())
    @assert expr.head in (:import, :using) && length(expr.args) >= 1
    # Handle multiple imports on one line
    if length(expr.args) > 1
        out_expr = quote end
        for item in expr.args
            pkg_sym_out = Ref(:(!))
            out_item = _macro_repl_import(Expr(expr.head, item),
                                          mod, reset=reset,
                                          pkg_sym_out=pkg_sym_out,
                                          already_reset=already_reset)
            push!(already_reset, pkg_sym_out[])
            push!(out_expr.args, out_item)
        end
        return out_expr
    end

    syms = import_expr_package_syms(expr)
    i = 1
    while i<length(syms) && syms[i] == :(.)
        i += 1
    end
    relative = i-1
    @assert syms[i] != :(.)
    pkg_name = string(syms[i])
    pkg_sym_out[] = syms[i]
    if syms[i] in already_reset
        reset = false
    end
    if relative > 0
        expr = import_expr_package_syms!(expr, :(.), syms...)
    end
    path = syms[i:end-isexpr(expr, :import)]
    quote
        $(_do_temporary_import)($pkg_name, $path, $(Core.Box(expr)), $mod,
                                $relative, $reset)
    end
end

function _do_temporary_import(pkg_name, path, expr_box, mod::Module,
                              relative::Int, reset::Bool)
    cleanup_dict = actual_getproperty(mod, :䷀import_variables,
                                      Dict{String, Set{Symbol}}())
    module_dict = actual_getproperty(mod, :䷀import_modules,
                                     Dict{String, Module}())

    # Make temporary module
    # Reload and import the package
    if relative > 0
        in_mod = mod
        for i in 2:relative
            in_mod = parentmodule(in_mod)
        end
        tmp_mod_sym = _get_temp_symbol(mod, Symbol("Mod䷀"*pkg_name), true)
        out_mod = Base.eval(mod, :(
            module $tmp_mod_sym
                $(expr_box.contents)
            end
        ))
        pkg_name = "."^relative * pkg_name
    else
        in_mod = _reload_package(mod, pkg_name, force=reset)
        out_mod = Module(:䷀)
        Base.eval(out_mod, expr_box.contents)
    end
    sub_in_mod = in_mod
    if length(path) >= 1
        for s in path[1+(relative==0):end]
            t = getproperty(sub_in_mod, s)
            t isa Module || break
            sub_in_mod = t
        end
    end

    if reset
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
    end

    # Assign the correct variables to the imported names
    expr = quote end
    @assert isexpr(expr, :block)
    all_names = _exported_names(out_mod, sub_in_mod,
                                [:䷀, Symbol("Mod䷀"*pkg_name)])
    if reset
        # Clear old values
        for sym in get(cleanup_dict, pkg_name, Set{Symbol}())
            assignment = :($sym = $no_longer_defined)
            push!(expr.args, assignment)
        end
    end
    # Set new values
    for sym in all_names
        push!(expr.args, :($sym = $out_mod.$sym))
    end
    # Save names for later cleanup
    if reset || !haskey(cleanup_dict, pkg_name)
        cleanup_dict[pkg_name] = all_names
    else
        union!(cleanup_dict[pkg_name], all_names)
    end
    push!(expr.args, :(䷀import_variables = $cleanup_dict))
    push!(expr.args, :(䷀import_modules = $module_dict))
    Base.eval(mod, expr)
    nothing
end


function is_include_expr(expr)
    isexpr(expr, :call) && length(expr.args) == 2 && expr.args[1] == :include
end

"""
Helper for `@repl include(...)` and `@repl include(...) ...`.
"""
function _macro_repl_include(mod::Module, exprs...)
    @assert is_include_expr(exprs[1])
    quote
        $(_do_temporary_include)($exprs, $mod)
    end
end

function _do_temporary_include(exprs, mod::Module)
    # Make temporary module
    out_mod = Module(:䷀, true)
    Base.eval(out_mod,
              :(include(path::AbstractString) = Base.include($out_mod, path)))
    for expr in exprs
        Base.eval(out_mod, expr)
    end

    # Assign the correct variables to the imported names
    expr = quote end
    @assert isexpr(expr, :block)
    all_names = setdiff!(actual_all_names(out_mod, false), [:䷀])
    # Set new values
    for sym in all_names
        push!(expr.args, :($sym = $out_mod.$sym))
    end
    Base.eval(mod, expr)
    nothing
end
