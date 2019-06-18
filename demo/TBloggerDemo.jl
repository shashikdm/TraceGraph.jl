using TensorBoardLogger
using TraceGraph

function foo(a)
    b = a+10
    c = b+10
    return (a,b,c)
end

tg = tracegraph(foo, 100)
lgr = TBLogger("tblog", tb_overwrite)
log_graph(lgr, "demo", tg.g, step = 1, nodelabel = tg.nodelabel, nodeop = tg.nodeop, nodevalue = tg.nodevalue)
