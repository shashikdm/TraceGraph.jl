function custom_repr(x)
    s = repr(x)
    if occursin("getfield(", s)
        s = String(match(r"\".*?\"", s).match)
    end
    return s
end

function insertnode!(valrefs::Dict{UInt64, Int64}, nodelist::Vector{TNode}, uniquenames::Dict{String, Int64}, prefix::String, name::String, op::String, val::Any)
    completename = prefix*name
    if haskey(uniquenames, completename)
        uniquenames[completename] += 1
        completename = completename*"_$(uniquenames[completename])"
    else
        uniquenames[completename] = 0
    end
    dtype = typeof(val)
    sz = ()
    if isa(val, AbstractArray)
        sz = size(val)
    push!(nodelist, TNode(completename, op, dtype, sz))
    valrefs[objectid(val)] = length(nodelist)
end

function getnodeid(valrefs::Dict{UInt64, Int64}, val::Any)
    oid = objectid(val)
    if haskey(valrefs, oid)
        return valrefs[oid]
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

mutable struct TraceData
    ignorelist::Vector{Any}
    valrefs::Dict{UInt64, Int64}
    nodelist::Vector{TNode}
    uniquenames::Dict{String, Int64}
    prefix::AbstractString
    G::SimpleDiGraph
end
ignorelist = [+, -, *, /]
Cassette.@context TraceCtx
function Cassette.prehook(ctx::TraceCtx, f, args...)
    result = f(args...)
    if f in ctx.metadata.ignorelist || !Cassette.canrecurse(ctx, f, args...)
        insertnode!(ctx.metadata.valrefs, ctx.metadata.nodelist, ctx.metadata.uniquenames, ctx.metadata.prefix, custom_repr(f), custom_repr(f), result)
        add_vertex!(ctx.metadata.G)
        resultid = nv(ctx.metadata.G)
        for arg in args
            nodeid = getnodeid(ctx.metadata.valrefs, arg)
            if nodeid == nothing
                insertnode!(ctx.metadata.valrefs, ctx.metadata.nodelist, ctx.metadata.uniquenames, ctx.metadata.prefix, custom_repr(arg), custom_repr(arg), arg)
                add_vertex!(ctx.metadata.G)
                nodeid = nv(ctx.metadata.G)
            end
            add_edge!(ctx.metadata.G, nodeid, resultid)
        end
    else
        ctx.metadata.prefix = ctx.metadata.prefix*custom_repr(f)*"/"
        last = findlast(isequal('/'), ctx.metadata.prefix)
    end
end
function Cassette.posthook(ctx::TraceCtx, f, args...)
    if f in ctx.metadata.ignorelist || !Cassette.canrecurse(ctx, f, args...)
    else
        last = findlast(isequal('/'), ctx.metadata.prefix)
        if last != nothing
            ctx.metadata.prefix = ctx.metadata.prefix[1:last-1]
        end
    end
end
"""
    generategraph(f::Function, args...)
Creates an object of type TGraph
"""
function generategraph(f, args...)
    tracedata = TraceData(ignorelist, Dict{UInt64, Int64}(), Vector{TNode}(), Dict{String, Int64}(), "", DiGraph())
    for func in ignorelist
        @eval Cassette.overdub(ctx::TraceCtx, ::typeof($func), args...) = $func(args...)
    end
    tracectx = TraceCtx(metadata = tracedata)
    Cassette.overdub(tracectx, f, args...)
    TGraph(tracedata.G, tracedata.nodelist, getnodelabels(tracedata.nodelist))
end
