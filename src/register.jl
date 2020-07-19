_has_registered = false

function register_auto()
    if !isdefined(Main, :IJulia)
        println("Error: Auto macros are only supported in IJulia.")
        return
    end
    if !isdefined(Main.IJulia, :cell_macros)
        println(
            "Error: This version of IJulia doesn't support auto macros.")
        return
    end
    if _has_registered
        return
    end
    push!(Main.IJulia.cell_macros, var"@repl")
    _has_registered = true
    nothing
end
