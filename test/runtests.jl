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
@testset "Conditional Statement" begin
    function foo(a::Bool)
        if a == true
            return 100+100
        else
            return 100-100
        end
    end
    gd = tracegraph(foo, false)
    gd = tracegraph(foo, true)
end
