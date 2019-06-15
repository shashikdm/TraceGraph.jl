using Test
using TraceGraph
using TraceGraph:tracegraph
using GraphPlot
using LightGraphs

@testset "Basic Tests" begin
    function foo(a)
            b = a+10
            c = b+10
            return (a,b,c)
    end
    gd = tracegraph(foo, 100)
    add_norecurse(reshape)
    show_norecurse()
    rm_norecurse(reshape)
end
