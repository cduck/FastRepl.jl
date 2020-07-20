_has_registered = false

function _test_ijulia(quiet)
    if !isdefined(Main, :IJulia)
        quiet || println("Error: Auto macros are only supported in IJulia.")
        return false
    end
    if !isdefined(Main.IJulia, :cell_macros)
        quiet || println(
            "Error: This version of IJulia doesn't support auto macros.")
        return false
    end
    true
end

function register_auto(; quiet=false)
    _test_ijulia(quiet) || return
    global _has_registered
    _has_registered && return
    push!(Main.IJulia.cell_macros, var"@repl")
    _has_registered = true
    nothing
end

function unregister_auto(; quiet=false)
    _test_ijulia(quiet) || return
    _has_registered || return
    i = findlast(f -> f == var"@repl", Main.IJulia.cell_macros)
    i === nothing && return
    splice!(Main.IJulia.cell_macros, i)
end
