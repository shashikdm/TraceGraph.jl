using Cassette
using Flux
using LightGraphs
using GraphPlot

G = DiGraph()

Cassette.@context TraceCtx

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

Cassette.prehook(ctx::TraceCtx, args...) = enter!(ctx.metadata, args...)
Cassette.posthook(ctx::TraceCtx, args...) = exit!(ctx.metadata)
trace = Trace()

Cassette.overdub(TraceCtx(metadata = trace), +, 10,20)

struct Node
    name::String
    op::String
    val::Any
end

nodelist = Array{Node, 1}()

function nodeexists(val::Any)
    for (n, node) in enumerate(nodelist)
        if node.val === val
            return n
        end
    end
    return false
end

function getnodenames(nodelist)
    names = Array{String, 1}()
    for node in nodelist
        push!(names, node.name)
    end
    return names
end

for t in trace.current
    line = t[1]
    call = t[1][1]
    args = t[1][2:end]
    result = t[1][1](t[1][2:end]...)
    push!(nodelist, Node(repr(t[1]), repr(t[1]), result))
    resultref = size(nodelist, 1)
    add_vertex!(G)
    for arg in args
        if nodeexists(arg) == false
            push!(nodelist, Node(repr(arg), repr(arg), arg))
            add_vertex!(G)
            add_edge!(G, size(nodelist, 1), resultref)
        else
            add_edge!(G, nodeexists(arg), resultref)
        end
    end
end
gplothtml(G, nodelabel=getnodenames(), NODESIZE = 0.20)
