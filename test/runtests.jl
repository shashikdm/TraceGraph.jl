using Test
using TraceGraph
using TraceGraph:generategraph
using GraphPlot
using Flux

@testset "Basic Tests" begin
    tg = generategraph(+, 1, 2)
    gplothtml(tg.graph, nodelabel = tg.labels)

    function foo(x)
        x = x+1
    end

    function bar(y)
        y = foo(y-1)
    end

    tg = generategraph(bar, 10)
    gplothtml(tg.graph, nodelabel = tg.labels)

    tg = generategraph(Conv((2, 2), 1=>1), rand(2, 2, 1, 1))
    gplothtml(tg.graph, nodelabel = tg.labels)
end
