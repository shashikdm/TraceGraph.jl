norecurselist = ["+", "-", "/", "*"]

function add_norecurse(f::String)
    global norecurselist
    if findfirst(isequal(f), norecurselist) == nothing
        push!(norecurselist, f)
    end
end

add_norecurse(f::Method) = add_norecurse(string(f.name))

function add_norecurse(f::Function)
    if !isa(f, Core.Builtin)
        add_norecurse(string(first(methods(f)).name))
    end
end

function rm_norecurse(f::String)
    global norecurselist
    index = findfirst(isequal(f), norecurselist)
    if findfirst(isequal(f), norecurselist) == nothing
        deleteat!(norecurselist, index)
    end
end

rm_norecurse(f::Method) = rm_norecurse(string(f.name))

function rm_norecurse(f::Function)
    if !isa(f, Core.Builtin)
        rm_norecurse(string(first(methods(f)).name))
    end
end

function show_norecurse()
    global norecurselist
    for s in norecurselist
        println(s)
    end
end
