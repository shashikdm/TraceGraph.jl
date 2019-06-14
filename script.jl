using Cassette
using LightGraphs
using DataStructures
using InteractiveUtils
using GraphPlot
Cassette.@context TraceCtx

slotname(ir::Core.CodeInfo, slotnum::Integer) = string(ir.slotnames[slotnum])
slotname(ir::Core.CodeInfo, slotnum) = slotname(ir, slotnum.id)

mutable struct GraphData
    g::SimpleDiGraph
    nodenames::Vector{String}
    depth::Int64
    argrefs::Vector{Queue{Vector{Int64}}}
    prefix::Vector{String}
end

ignorelist = []

function Cassette.prehook(ctx::TraceCtx, f, args...)
    ir = InteractiveUtils.@code_lowered f(args...)
    gdata = ctx.metadata
    @show "prehook" f gdata.depth gdata.argrefs[gdata.depth]
    orgargs = dequeue!(gdata.argrefs[gdata.depth])
    if Cassette.canrecurse(ctx, f, args...) == false
        #can't recurse then create nodes for result and args
        push!(gdata.prefix, repr(f))
        push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*repr(f))
        add_vertex!(gdata.g)
        resultref = nv(gdata.g)
        for (n, arg) in enumerate(args)
            #create node for each argument
            push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*repr(arg))
            add_vertex!(gdata.g)
            #also connect
            add_edge!(gdata.g, orgargs[n], nv(gdata.g))
            add_edge!(gdata.g, nv(gdata.g), resultref)
        end
        add_edge!(gdata.g, resultref, last(orgargs))
        #gplothtml(gdata.g, nodelabel = [repr(y) for y in enumerate(gdata.nodenames)])
        return nothing
    end
    method = methods(f, Tuple([typeof(arg) for arg in args])).ms[1]
    name = method.name
    push!(gdata.prefix, string(name))
    localnodes = Dict{Any, Int64}()
    argnames = Base.method_argnames(method)[2:end]
    @assert length(argnames)+1 == length(orgargs)
    for (n, arg) in enumerate(argnames)
        #create a node for each argument
        push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*string(arg))
        add_vertex!(gdata.g)
        localnodes[Core.SlotNumber(findfirst(isequal(arg), ir.slotnames))] = nv(gdata.g)
        #also connect these arguments to the parent function
        add_edge!(gdata.g, orgargs[n], nv(gdata.g))
    end
    if name in ignorelist
        #if this is to be ignored, then just make one node for result
        push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*string(name))
        add_vertex!(gdata.g)
        resultref = nv(gdata.g)
        for v in values(localnodes)
            add_edge!(gdata.g, v, resultref)
        end
        add_edge!(gdata.g, resultref, last(orgargs))
    else
        #build subgraph
        q = Queue{Vector{Int64}}()
        for (n, line) in enumerate(ir.code)
            arglist = Vector{Int64}()
            if line.head == :(=)
                #assignment
                #create node for lhs
                lhs = line.args[1]
                push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*slotname(ir, lhs))
                add_vertex!(gdata.g)
                lhsref = nv(gdata.g)
                localnodes[lhs] = lhsref
                rhs = line.args[2]
                if isa(rhs, Expr)
                    if rhs.head == :call
                        #this is a function call
                        #expose args and recurse will take care
                        args = rhs.args[2:end]
                        for arg in args
                            if isa(arg, Core.SlotNumber) || isa(arg, Core.SSAValue)
                                argref = localnodes[arg]
                                push!(arglist, argref)
                            elseif isa(arg, Number)
                                push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*string(arg))
                                add_vertex!(gdata.g)
                                push!(arglist, nv(gdata.g))
                            else
                                @error "unhandled $arg"
                            end
                        end
                        push!(arglist, lhsref)
                    end
                elseif isa(rhs, Core.SlotNumber) || isa(rhs, Core.SSAValue)
                    #this is a variable assignment
                    # or this is ssavalue temporary variable
                    rhsref = localnodes[rhs]
                    add_edge!(gdata.g, rhsref, lhsref)
                elseif isa(rhs, Number)
                    #this is a constant
                    push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*repr(rhs))
                    add_vertex!(gdata.g)
                    rhsref = nv(gdata.g)
                    add_edge!(gdata.g, rhsref, lhsref)
                else
                    @error "unhandled $rhs"
                end
            elseif line.head == :call
                lhs = Core.SSAValue(n)
                push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*string(lhs))
                add_vertex!(gdata.g)
                lhsref = nv(gdata.g)
                localnodes[lhs] = lhsref
                #this is function call
                #expose args and output and recurse will take care
                args = line.args[2:end]
                for arg in args
                    if isa(arg, Core.SlotNumber) || isa(arg, Core.SSAValue)
                        argref = localnodes[arg]
                        push!(arglist, argref)
                    elseif isa(arg, Number)
                        push!(gdata.nodenames, join(gdata.prefix, "/")*"/"*string(arg))
                        add_vertex!(gdata.g)
                        push!(arglist, add_vertex!(gdata.g))
                    else
                        @error "unhandled $arg"
                    end
                end
                push!(arglist, lhsref)
            elseif line.head == :return
                lhsref = last(orgargs)
                rhsref = localnodes[line.args[1]]
                add_edge!(gdata.g, rhsref, lhsref)
            else
                @error "unhandled $(line.head)"
            end
            enqueue!(q, arglist)
        end
    end
    push!(gdata.argrefs, q)
    gdata.depth = gdata.depth+1
    #gplothtml(gdata.g, nodelabel = [repr(y) for y in enumerate(gdata.nodenames)])
end
function Cassette.posthook(ctx::TraceCtx, output, f, args...)
    gdata = ctx.metadata
    if Cassette.canrecurse(ctx, f, args...) == true
        pop!(gdata.argrefs)
        gdata.depth = gdata.depth-1
    end
    pop!(gdata.prefix)
    @show "posthook" typeof(f) gdata.depth gdata.argrefs[gdata.depth]
end
function buildgraph(f, args...)
    gdata = GraphData(DiGraph(), Vector{String}(), 1, [], Vector{String}())
    q = Queue{Vector{Int64}}()
    noderefs = Vector{Int64}()
    for arg in args
        push!(gdata.nodenames, "inp")
        add_vertex!(gdata.g)
        push!(noderefs, nv(gdata.g))
    end
    push!(gdata.nodenames, "output")
    add_vertex!(gdata.g)
    push!(noderefs, nv(gdata.g))
    enqueue!(q, noderefs)
    push!(gdata.argrefs, q)
    ctx = TraceCtx(;metadata = gdata)
    Cassette.prehook(ctx, f, args...)
    Cassette.overdub(ctx, f, args...)
    Cassette.posthook(ctx, f, args...)
    return gdata
end

function foo(a)
        b = a+10
        c = b+10
        return (a,b,c)
end
gd = buildgraph(foo, 100)
gplothtml(gd.g, nodelabel = gd.nodenames)
