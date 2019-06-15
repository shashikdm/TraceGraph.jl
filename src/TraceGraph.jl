module TraceGraph

using Cassette
using LightGraphs
import LightGraphs: add_vertex!, add_edge!
using DataStructures
using InteractiveUtils

"""
    struct TGraph
Object that represents the traced graph of the function call.
fields:
- g::SimpleDiGraph  : Object of type SimpleDiGraph
- nodelabel::Vector{String} : List of names corresponding to the nodes
- nodeop::Vector{String} : List of names of operations of the nodes
- nodeval::Vector{Any} : List of values of ndoes
"""
struct TGraph
    g::SimpleDiGraph
    nodelabel::Vector{String}
    nodeop::Vector{String}
    nodevalue::Vector{Any}
end

include("NoRecurseList.jl")
include("GenerateGraph.jl")

export TGraph, tracegraph
export add_norecurse, rm_norecurse, show_norecurse

end # module
