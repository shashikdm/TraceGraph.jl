####### Cassette pass #######
mutable struct Trace
    current::Vector{Any}
    stack::Vector{Any}
    Trace() = new(Any[], Any[])
end

function enter!(t::Trace, args...)
    pair = args => Any[]
    push!(t.current, pair)
    push!(t.stack, t.current)
    t.current = pair.second
    return nothing
end

function exit!(t::Trace)
    t.current = pop!(t.stack)
    return nothing
end

###### Library ######

function custom_repr(x)
    s = repr(x)
    if occursin("getfield(", s)
        s = String(match(r"\".*?\"", s).match)
    end
    return s
end


"""
    struct TNode
Object corresponding to every vertex in graph
fields:
- name::String  : Unique name for each node
- op::String    : Name of the function/operation
- val::Any      : Content of the node (if any)
"""

struct TNode
    name::String
    op::String
    val::Any
end

function insertnode!(nodelist::Vector{TNode}, localnodelist::Vector{TNode}, uniquenames::Dict{String, Int64}, prefix::String, name::String, op::String, val::Any)
    completename = prefix*name
    if haskey(uniquenames, completename)
        uniquenames[completename] += 1
        push!(nodelist, TNode(completename*"_"*repr(uniquenames[completename]), op, val))
        push!(localnodelist, TNode(completename*"_"*repr(uniquenames[completename]), op, val))
    else
        uniquenames[completename] = 0
        push!(nodelist, TNode(completename, op, val))
        push!(localnodelist, TNode(completename, op, val))
    end
end

function getnoderef(nodelist::Vector{TNode}, localnodelist::Vector{TNode}, val::Any)
    for lnode in localnodelist
        if lnode.val === val
            for (n, node) in enumerate(reverse(nodelist))
                if node.val === val
                    return size(nodelist, 1)+1-n
                end
            end
        end
    end
    return nothing
end

function getnodelabels(nodelist::Vector{TNode})
    names = Array{String, 1}()
    for node in nodelist
        push!(names, node.name)
    end
    return names
end

ignorelist = [+, -, *, /]
"""
    struct TGraph
Object that represents the traced graph of the function call.
fields:
- graph::SimpleDiGraph  : Object of type SimpleDiGraph
- names::Vector{String} : List of names corresponding to the nodes
"""

struct TGraph
    graph::SimpleDiGraph
    nodelist::Vector{TNode}
    labels::Vector{String}
end

"""
    generategraph(f::Function, args...)
Creates an object of type TGraph
"""

Cassette.@context TraceCtx
Cassette.prehook(ctx::TraceCtx, args...) = enter!(ctx.metadata, args...)
Cassette.posthook(ctx::TraceCtx, args...) = exit!(ctx.metadata)

function generategraph(f, args...)
    G = DiGraph()
    trace = Trace()
    Cassette.overdub(TraceCtx(metadata = trace), f, args...)
    nodelist = Vector{TNode}()
    uniquenames = Dict{String, Int64}()
    prefix = ""
    function buildgraph(trace::Array{Any, 1}, lnodelist::Vector{TNode})
        for t in trace
            line = t.first
            call = line[1]
            args = line[2:end]
            result = call(args...)
            if isempty(t.second) || call in ignorelist #no subgraph
                insertnode!(nodelist, lnodelist, uniquenames, prefix, custom_repr(call), custom_repr(call), result)
                add_vertex!(G)
                resultref = nv(G)
                for arg in args
                    noderef = getnoderef(nodelist, lnodelist, arg)
                    if noderef == nothing #new node
                        insertnode!(nodelist, lnodelist, uniquenames, prefix, custom_repr(arg), custom_repr(arg), arg)
                        add_vertex!(G)
                        noderef = nv(G)
                    end
                    add_edge!(G, noderef, resultref) #connect result and arg
                end
            else #subgraph

                #Step 1 create arg nodes and a result node

                newlocalnodelist = Vector{TNode}()
                for arg in args
                    #for each arg make node in both caller and callee
                    noderef1 = getnoderef(nodelist, lnodelist, arg)
                    if noderef1 == nothing #new node
                        insertnode!(nodelist, lnodelist, uniquenames, prefix, custom_repr(arg), custom_repr(arg), arg)
                        add_vertex!(G)
                        noderef1 = nv(G)
                    end
                    #now make arg node in that function
                    insertnode!(nodelist, newlocalnodelist, uniquenames, prefix*custom_repr(call)*"/", custom_repr(arg), custom_repr(arg), arg)
                    add_vertex!(G)
                    noderef2 = nv(G)
                    add_edge!(G, noderef1, noderef2) #connect result and arg
                end
                #Then build subgraph
                oldprefix = prefix
                prefix = prefix*custom_repr(call)*"/"
                buildgraph(t.second, newlocalnodelist)
                #Then add the last node in subgraph to local nodelist
                push!(lnodelist, last(newlocalnodelist))
            end
        end
    end
    buildgraph(trace.current, Vector{TNode}())
    TGraph(G, nodelist, getnodelabels(nodelist))
end
