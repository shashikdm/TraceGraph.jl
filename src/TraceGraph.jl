module TraceGraph

using Cassette
using LightGraphs

"""
    struct TNode
Object corresponding to every vertex in graph
fields:
- name::String      : Unique name for each node
- op::String        : Name of the function/operation
- dtype::DataType   : datatype of content
- size::Tuple       : size of the content
"""

struct TNode
    name::String
    op::String
    dtype::DataType
    size::Tuple
end

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

include("GenerateGraph.jl")

export TGraph, TNode, generategraph, ignorelist

end # module
