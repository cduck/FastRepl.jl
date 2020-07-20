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

function register_auto(; reset_flag=false, quiet=false)
    _test_ijulia(quiet) || return
    unregister_auto(quiet=quiet)
    mac = reset_flag ? var"@repl_reset" : var"repl"
    push!(Main.IJulia.cell_macros, mac)
    nothing
end

function unregister_auto(; quiet=false)
    _test_ijulia(quiet) || return
    remove_last_item!(Main.IJulia.cell_macros, var"@repl")
    remove_last_item!(Main.IJulia.cell_macros, var"@repl_reset")
end

function remove_last_item!(list, item)
    i = findlast(f -> f == item, list)
    i === nothing || splice!(list, i)
    list
end
