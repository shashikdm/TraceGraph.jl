# TraceGraph.jl

Generate directed graphs of the IR of a function call.

## Installation
]add https://github.com/shashikdm/TraceGraph.jl
## Usage
```
using TraceGraph
using GraphPlot
```
Declare your functions:
```
function foo(x)
    x = x+1
end

function bar(y)
    y = foo(y-1)
end
```
Call `generategraph` as follows
```
tracegraph = generategraph(bar, 10)
```
`tracegraph` is an object of type TGraph which consists of following fields:  
- `:graph` : Object of type SimpleDiGraph
- `:nodelist` : Vector of `TNode` which has fields:
    - `:name` : Unique name of the node as displayed in the graph
    - `:op` : Specifies the operation that it performs
    - `:val` : Content of the node (if any)
- `:labels` : Vector of `name` fields of `nodelist`

Then call `gplot` or `gplothtml` to plot the graph
```
gplot(tracegraph.graph, nodelabels = tracegraph.labels)
#OR
gplothtml(tracegraph.graph, nodelabels = tracegraph.labels)
```
The resulting plot will look something like :  
![foobargraph](https://raw.githubusercontent.com/shashikdm/TraceGraph.jl/de19aa12d31b70a684ba271d0c76b1e6be641bcb/foobargraph.png)
