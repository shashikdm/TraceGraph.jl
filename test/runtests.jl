using Test
using TraceGraph
using TraceGraph:generategraph
using GraphPlot
using Flux
using LightGraphs

@testset "Basic Tests" begin
    tg = generategraph(+, 1, 2)
    @test nv(tg.graph) == 3


    function foo(x)
        x = x+1
    end

    function bar(y)
        y = foo(y-1)
    end
    tg = generategraph(bar, 10)
    @test nv(tg.graph) == 7



    tg = generategraph(softmax, rand(2))
end
