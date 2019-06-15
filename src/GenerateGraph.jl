Cassette.@context TraceCtx

mutable struct GraphData
    tg::TGraph
    argrefs::Stack{Queue{Vector{Int64}}}
    prefix::Vector{String}
    uniquenames::Dict{String, Int64}
    valdict::Dict{Int64, Any}
end

function gen_label(gdata::GraphData, name::String)
    candidatename = name
    if haskey(gdata.uniquenames, candidatename)
        gdata.uniquenames[candidatename] += 1
        uniquename = candidatename*"_"*string(gdata.uniquenames[candidatename])
    else
        gdata.uniquenames[candidatename] = 0
        uniquename = candidatename
    end
    gen_prefix(gdata)*uniquename
end
function add_vertex!(gdata::GraphData, name::String, op::String)
    name = gen_label(gdata, name)
    push!(gdata.tg.nodelabel, name)
    push!(gdata.tg.nodeop, op)
    add_vertex!(gdata.tg.g)
    nv(gdata.tg.g)
end
function add_prefix!(gdata::GraphData, newprefix::String)
    candidatename = newprefix
    if haskey(gdata.uniquenames, candidatename)
        gdata.uniquenames[candidatename] += 1
        uniquename = candidatename*"_"*string(gdata.uniquenames[candidatename])
    else
        gdata.uniquenames[candidatename] = 0
        uniquename = candidatename
    end
    push!(gdata.prefix, uniquename)
end
rm_prefix!(gdata::GraphData) = pop!(gdata.prefix)
gen_prefix(gdata::GraphData) = join(gdata.prefix, "/")*"/"
add_val!(gdata::GraphData, node::Int64, val::Any) = gdata.valdict[node] = val

slotname(ir::Core.CodeInfo, slotnum::Integer) = string(ir.slotnames[slotnum])
slotname(ir::Core.CodeInfo, slotnum) = slotname(ir, slotnum.id)

function Cassette.prehook(ctx::TraceCtx, f, args...)
    #get the IR of this function call
    ir = InteractiveUtils.@code_lowered f(args...)
    gdata = ctx.metadata
    #obtain the exposed argument nodes for this function all
    orgargs = front(top(gdata.argrefs))
    @assert length(orgargs) == length(args)+1 "args length mismatch"
    if Cassette.canrecurse(ctx, f, args...) == false
        #can't recurse then create nodes just for result and args
        add_prefix!(gdata, repr(f))
        resultref = add_vertex!(gdata, repr(f), "function")
        for (n, arg) in enumerate(args)
            #create node for each argument
            argref = add_vertex!(gdata, repr(arg), "arg")
            #connect the exposed arg to this arg
            add_edge!(gdata.tg.g, orgargs[n], argref)
            #connect this arg to result
            add_edge!(gdata.tg.g, argref, resultref)
            add_val!(gdata, orgargs[n], arg)
            add_val!(gdata, argref, arg)
        end
        #connect exposed output with this result
        add_edge!(gdata.tg.g, resultref, last(orgargs))
        add_val!(gdata, resultref, f)
    else
        method = first(methods(f, map(typeof, args)))
        argnames = Base.method_argnames(method)[2:end]
        @assert length(orgargs) == length(argnames)+1 "argnames length mismatch"
        name = string(method.name)
        add_prefix!(gdata, name)
        #reference of localnodes for this function call
        localnodes = Dict{Any, Int64}()
        for (n, arg) in enumerate(argnames)
            #create a node for each argument
            argref =  add_vertex!(gdata, string(arg), "arg")
            localnodes[Core.SlotNumber(findfirst(isequal(arg), ir.slotnames))] = argref
            #also connect these arguments to the parent function
            add_edge!(gdata.tg.g, orgargs[n], argref)
            add_val!(gdata, orgargs[n], args[n])
            add_val!(gdata, argref, args[n])
        end

        if name in norecurselist
            #if this is to be ignored, then just make one node for result
            resultref = add_vertex!(gdata, string(name), "function")
            for v in values(localnodes)
                add_edge!(gdata.tg.g, v, resultref)
            end
            add_edge!(gdata.tg.g, resultref, last(orgargs))
            add_val!(gdata, resultref, f)
        else
            #build subgraph
            q = Queue{Vector{Int64}}()
            for (n, line) in enumerate(ir.code)
                arglist = Vector{Int64}()
                if line.head == :(=) #assignment
                    #create node for lhs
                    lhs = first(line.args)
                    lhsref = add_vertex!(gdata, slotname(ir, lhs), "variable")
                    localnodes[lhs] = lhsref
                    rhs = last(line.args)
                    if rhs isa Expr
                        if rhs.head == :call
                            #this is a function call
                            #expose args and recurse will take care
                            args = rhs.args[2:end]
                            for arg in args
                                if arg isa Core.SlotNumber || arg isa Core.SSAValue
                                    #so it already exists in localnodes
                                    argref = localnodes[arg]
                                    push!(arglist, argref)
                                elseif arg isa Number
                                    #create new node for this
                                    argref = add_vertex!(gdata, repr(arg), "constant")
                                    add_val!(gdata, argref, arg)
                                    push!(arglist, argref)
                                else
                                    @error "unhandled rhs arg $arg"
                                end
                            end
                            push!(arglist, lhsref)
                        else
                            #some arent handled yet, invoke, goto etc
                            @error "unhandled rhs head $rhs"
                        end
                    elseif rhs isa Core.SlotNumber || rhs isa Core.SSAValue
                        rhsref = localnodes[rhs]
                        add_edge!(gdata.tg.g, rhsref, lhsref)
                    elseif rhs isa Number
                        #this is a constant
                        rhsref = add_vertex!(gdata, repr(rhs), "constant")
                        add_val!(gdata, argref, arg)
                        add_edge!(gdata.tg.g, rhsref, lhsref)
                    else
                        @error "unhandled rhs $rhs"
                    end
                elseif line.head == :call
                    #create node for this ssavalue
                    lhs = Core.SSAValue(n)
                    lhsref = add_vertex!(gdata, repr(lhs), "SSAValue")
                    localnodes[lhs] = lhsref
                    #this is function call
                    #expose args and output and recurse will take care
                    args = line.args[2:end]
                    for arg in args
                        if arg isa Core.SlotNumber || arg isa Core.SSAValue
                            argref = localnodes[arg]
                        elseif arg isa Number
                            argref = add_vertex!(gdata, repr(arg), "constant")
                            add_val!(gdata, argref, arg)
                        else
                            @error "unhandled call arg $arg"
                        end
                        push!(arglist, argref)
                    end
                    push!(arglist, lhsref)
                elseif line.head == :return
                    lhsref = last(orgargs)
                    rhsref = localnodes[first(line.args)]
                    add_edge!(gdata.tg.g, rhsref, lhsref)
                else
                    @error "unhandled line $(line.head)"
                end
                enqueue!(q, arglist)
            end
            push!(gdata.argrefs, q)
        end
    end
end
function Cassette.overdub(ctx::TraceCtx, f, args...)
    if Cassette.canrecurse(ctx, f, args...) == false
        return Cassette.fallback(ctx, f, args...)
    end
    method = first(methods(f, map(typeof, args)))
    name = string(method.name)
    if name in norecurselist
        return Cassette.fallback(ctx, f, args...)
    end
    return Cassette.recurse(ctx, f, args...)
end
function Cassette.posthook(ctx::TraceCtx, output, f, args...)
    gdata = ctx.metadata
    if Cassette.canrecurse(ctx, f, args...) == true
        method = first(methods(f, map(typeof, args)))
        if !(string(method.name) in norecurselist)
            pop!(gdata.argrefs)
        end
    end
    orgargs = dequeue!(top(gdata.argrefs))
    @show f gdata.argrefs args
    @assert length(orgargs) == length(args) + 1
    add_val!(gdata, last(orgargs), output)
    pop!(gdata.prefix)
end

"""
    tracegraph(f::Function, args...)
Creates an object of type TGraph
"""
function tracegraph(f, args...)
    #prepare metadata for cassette
    tg = TGraph(DiGraph(), String[], String[], [])
    gdata = GraphData(tg, Stack{Queue{Vector{Int64}}}(), String[], Dict{String, Int64}(), Dict{Int64, Any}())
    #expose input nodes and output node for the function call
    #insert this list of node numbers in a queue in a stack
    noderefs = Int64[]
    for arg in args
        noderef = add_vertex!(gdata, "input", "input")
        push!(noderefs, noderef)
    end
    noderef = add_vertex!(gdata, "output", "output")
    push!(noderefs, noderef)
    q = Queue{Vector{Int64}}()
    enqueue!(q, noderefs)
    push!(gdata.argrefs, q)
    #Call cassette
    ctx = TraceCtx(metadata = gdata)
    Cassette.prehook(ctx, f, args...)
    out = Cassette.overdub(ctx, f, args...)
    Cassette.posthook(ctx, out, f, args...)
    for v in vertices(gdata.tg.g)
        if haskey(gdata.valdict, v)
            push!(gdata.tg.nodeval, gdata.valdict[v])
        else
            push!(gdata.tg.nodeval, nothing)
        end
    end
    gdata.tg
end
