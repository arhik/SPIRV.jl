function entry_node(g::AbstractGraph)
  vs = sources(g)
  isempty(vs) && error("No entry node was found.")
  length(vs) > 1 && error("Multiple entry nodes were found.")
  first(vs)
end

sinks(g::AbstractGraph) = vertices(g)[findall(isempty ∘ Fix1(outneighbors, g), vertices(g))]
sources(g::AbstractGraph) = vertices(g)[findall(isempty ∘ Fix1(inneighbors, g), vertices(g))]

@auto_hash_equals struct SimpleTree{T}
  data::T
  parent::Optional{SimpleTree{T}}
  children::Vector{SimpleTree{T}}
end

"""
Equality is defined for `SimpleTree`s over data and children. The equality of
parents is not tested to avoid infinite recursion, and only the presence of
parents is tested instead.
"""
Base.:(==)(x::SimpleTree{T}, y::SimpleTree{T}) where {T} = x.data == y.data && x.children == y.children && isnothing(x.parent) == isnothing(y.parent)
SimpleTree(data::T) where {T} = SimpleTree{T}(data)
SimpleTree{T}(data::T) where {T} = SimpleTree{T}(data, nothing, T[])

SimpleTree(data::T, children) where {T} = SimpleTree{T}(data, children)
function SimpleTree{T}(data::T, children) where {T}
  tree = SimpleTree(data)
  for c in children
    push!(tree.children, @set c.parent = tree)
  end
  tree
end

Base.show(io::IO, ::MIME"text/plain", tree::SimpleTree) = isempty(children(tree)) ? print(io, typeof(tree), "(", tree.data, ", [])") : print(io, chomp(sprintc(print_tree, tree; maxdepth = 10)))
Base.show(io::IO, tree::SimpleTree) = print(io, typeof(tree), "(", nodevalue(tree), isroot(tree) ? "" : string(", parent = ", nodevalue(parent(tree))), ", children = [", join(nodevalue.(children(tree)), ", "), "])")

Base.getindex(tree::SimpleTree, index) = children(tree)[index]

AbstractTrees.nodetype(T::Type{<:SimpleTree}) = T
AbstractTrees.NodeType(::Type{SimpleTree{T}}) where {T} = HasNodeType()
AbstractTrees.nodevalue(tree::SimpleTree) = tree.data
AbstractTrees.ChildIndexing(::Type{<:SimpleTree}) = IndexedChildren()

AbstractTrees.ParentLinks(::Type{<:SimpleTree}) = StoredParents()
AbstractTrees.parent(tree::SimpleTree) = tree.parent

AbstractTrees.children(tree::SimpleTree) = tree.children
AbstractTrees.childrentype(::Type{T}) where {T<:SimpleTree} = T

struct SpanningTreeDFS{G<:AbstractGraph}
  tree::G
  discovery_times::Vector{Int}
  finish_times::Vector{Int}
end

function SpanningTreeDFS(g::AbstractGraph{T}, source = 1) where {T}
  tree = typeof(g)(nv(g))
  dfst = SpanningTreeDFS(tree, zeros(Int, nv(g)), zeros(Int, nv(g)))
  build!(dfst, [source], zeros(Bool, nv(g)), g)
  dfst
end

function build!(dfst::SpanningTreeDFS, next, visited, g::AbstractGraph, time = 0)
  v = pop!(next)
  visited[v] = true
  dfst.discovery_times[v] = (time += 1)
  for w in outneighbors(g, v)
    if !visited[w]
      add_edge!(dfst.tree, v, w)
      push!(next, w)
      time = build!(dfst, next, visited, g, time)
    end
  end
  dfst.finish_times[v] = (time += 1)

  time
end

pre_ordering(dfst::SpanningTreeDFS) = sortperm(dfst.discovery_times)
post_ordering(dfst::SpanningTreeDFS) = sortperm(dfst.finish_times)

struct EdgeClassification{E<:AbstractEdge}
  tree_edges::Set{E}
  forward_edges::Set{E}
  retreating_edges::Set{E}
  cross_edges::Set{E}
end

EdgeClassification{E}() where {E} = EdgeClassification(Set{E}(), Set{E}(), Set{E}(), Set{E}())

function SimpleTree(dfst::SpanningTreeDFS, parent::Union{Nothing, SimpleTree{T}}, v::T) where {T}
  tree = SimpleTree(v, parent, SimpleTree{T}[])
  for w in outneighbors(dfst.tree, v)
    push!(tree.children, SimpleTree(dfst, tree, w))
  end
  tree
end

SimpleTree(dfst::SpanningTreeDFS) = SimpleTree(dfst, nothing, entry_node(dfst.tree))

EdgeClassification(g::AbstractGraph, dfst::SpanningTreeDFS = SpanningTreeDFS(g)) = EdgeClassification(g, SimpleTree(dfst))

function EdgeClassification(g::AbstractGraph{T}, tree::SimpleTree{T}) where {T}
  E = edgetype(g)
  ec = EdgeClassification{E}()
  for subtree in PreOrderDFS(tree)
    # Traverse the tree and classify edges based on ancestor information.
    # Outgoing edges are used to find retreating edges (if pointing to an ancestor).
    # Incoming edges are used to find tree edges (if coming from parent) and forward edges (if pointing to an ancestor that is not the parent).
    # Other edges are cross-edges.
    v = nodevalue(subtree)

    for u in inneighbors(g, v)
      e = E(u, v)
      nodevalue(parent(subtree))
      if u == nodevalue(parent(subtree))
        push!(ec.tree_edges, e)
      elseif !isnothing(find_parent(==(u) ∘ nodevalue, subtree))
        push!(ec.forward_edges, e)
      end
    end

    for w in outneighbors(g, v)
      e = E(v, w)
      !isnothing(find_parent(==(w) ∘ nodevalue, subtree)) && push!(ec.retreating_edges, e)
    end
  end

  for e in edges(g)
    !in(e, ec.tree_edges) && !in(e, ec.forward_edges) && !in(e, ec.retreating_edges) && push!(ec.cross_edges, e)
  end

  ec
end

struct ControlFlowGraph{E<:AbstractEdge,T,G<:AbstractGraph{T}} <: AbstractGraph{T}
  g::G
  dfst::SpanningTreeDFS{G}
  ec::EdgeClassification{E}
  is_reducible::Bool
  is_structured::Bool
  ControlFlowGraph(g::G, dfst::SpanningTreeDFS{G}, ec::EdgeClassification{E}, is_reducible::Bool, is_structured::Bool) where {T, G<:AbstractGraph{T}, E<:AbstractEdge} = new{E,T,G}(g, dfst, ec, is_reducible, is_structured)
end

@forward ControlFlowGraph.g (Graphs.vertices, Graphs.edges, Graphs.add_edge!, Graphs.edgetype, Graphs.add_vertex!, Graphs.rem_edge!, Graphs.rem_vertex!, Graphs.rem_vertices!, Graphs.inneighbors, Graphs.outneighbors, Graphs.nv, Graphs.ne, dominators)

Graphs.is_directed(::Type{<:ControlFlowGraph}) = true

Base.reverse(cfg::ControlFlowGraph) = ControlFlowGraph(reverse(cfg.g))

is_reducible(cfg::ControlFlowGraph) = cfg.is_reducible
is_structured(cfg::ControlFlowGraph) = cfg.is_structured

ControlFlowGraph(args...) = ControlFlowGraph(control_flow_graph(args...))

function ControlFlowGraph(cfg::AbstractGraph)
  dfst = SpanningTreeDFS(cfg)
  ec = EdgeClassification(cfg, dfst)

  analysis_cfg = deepcopy(cfg)
  rem_edges!(analysis_cfg, backedges(cfg, ec))
  is_reducible = !is_cyclic(analysis_cfg)

  # TODO: actually test whether CFG is structured or not.
  is_structured = is_reducible
  ControlFlowGraph(cfg, dfst, ec, is_reducible, is_structured)
end

control_flow_graph(fdef::FunctionDefinition) = control_flow_graph(collect(fdef.blocks))

function control_flow_graph(amod::AnnotatedModule, af::AnnotatedFunction)
  cfg = SimpleDiGraph(length(af.blocks))

  for (i, block) in enumerate(af.blocks)
    for inst in instructions(amod, block)
      (; arguments) = inst
      @tryswitch opcode(inst) begin
        @case &OpBranch
        dst = arguments[1]::SSAValue
        add_edge!(cfg, i, find_block(amod, af, dst))
        @case &OpBranchConditional
        dst1, dst2 = arguments[2]::SSAValue, arguments[3]::SSAValue
        add_edge!(cfg, i, find_block(amod, af, dst1))
        add_edge!(cfg, i, find_block(amod, af, dst2))
        @case &OpSwitch
        for dst in arguments[2:end]
          add_edge!(cfg, i, find_block(amod, af, dst::SSAValue))
        end
      end
    end
  end
  cfg
end

function find_block(amod::AnnotatedModule, af::AnnotatedFunction, id::SSAValue)
  for (i, block) in enumerate(af.blocks)
    has_result_id(amod[block.start], id) && return i
  end
end

function dominators(g::AbstractGraph{T}) where {T}
  doms = Set{T}[Set{T}() for _ in 1:nv(g)]
  source = entry_node(g)
  push!(doms[source], source)
  vs = filter(≠(source), vertices(g))
  for v in vs
    union!(doms[v], vertices(g))
  end

  converged = false
  while !converged
    converged = true
    for v in vs
      h = hash(doms[v])
      set = intersect((doms[u] for u in inneighbors(g, v))...)
      doms[v] = set
      push!(set, v)
      h ≠ hash(set) && (converged &= false)
    end
  end

  doms
end

function backedges(cfg::ControlFlowGraph)
  is_reducible(cfg) && return copy(cfg.ec.retreating_edges)
  backedges(cfg.g, cfg.ec)
end

function backedges(g::AbstractGraph{T}, ec::EdgeClassification = EdgeClassification(g), domsets::AbstractVector{Set{T}} = dominators(g)) where {T}
  filter(ec.retreating_edges) do e
    in(dst(e), domsets[src(e)])
  end
end

function remove_backedges(cfg::ControlFlowGraph)
  g = deepcopy(cfg.g)
  rem_edges!(g, backedges(cfg))
  ControlFlowGraph(g)
end

traverse(cfg::ControlFlowGraph) = reverse(post_ordering(cfg.dfst))

"""
Iterate through the graph `g` applying `f` until its application on the graph vertices
reaches a fixed point.

`f` must return a `Bool` value indicating whether a next iteration should be performed.
If `false`, then the iteration will not be continued on outgoing nodes.

# Flow Analysis

- Nodes that are not part of a cyclic structure (i.e. have no back-edges and don't have a path from a node which has a back-edge) need only be traversed once.
- Cyclic structures must be iterated on until convergence. On reducible control-flow graphs, it might be sufficient to iterate a given loop structure locally until convergence before iterating through nodes that are further apart in the cyclic structure. This optimization is not currently implemented.
- Flow analysis should provide a framework suited for both abstract interpretation and data-flow algorithms.
"""
function flow_through(f, cfg::ControlFlowGraph, v; stop_at::Optional{Union{Int, Edge{Int}}} = nothing)
  next = [Edge(v, v2) for v2 in outneighbors(cfg, v)]
  bedges = backedges(cfg)
  while !isempty(next)
    edge = popfirst!(next)
    ret = f(edge)
    isnothing(ret) && return
    in(edge, bedges) && !ret && continue

    stop_at isa Edge{Int} && edge === stop_at && continue
    stop_at isa Int && dst(edge) === stop_at && continue

    # Push all new edges to the end of the worklist.
    new_edges = [Edge(dst(edge), v) for v in outneighbors(cfg, dst(edge))]
    filter!(e -> !in(e, new_edges), next)
    append!(next, new_edges)
  end
end

function postdominator(cfg::ControlFlowGraph, source)
  cfg = remove_backedges(cfg)
  root_tree = DominatorTree(cfg)
  tree = nothing
  for subtree in PreOrderDFS(root_tree)
    if node(subtree) == source
      tree = subtree
    end
  end
  pdoms = findall(!in(v, outneighbors(cfg, node(tree))) for v in immediate_postdominators(tree))
  @assert length(pdoms) ≤ 1 "Found $(length(pdoms)) postdominator(s)"
  isempty(pdoms) ? nothing : node(tree[only(pdoms)])
end

struct DominatorNode
  index::Int
end

const DominatorTree = SimpleTree{DominatorNode}

node(tree::DominatorTree) = nodevalue(tree).index

immediate_postdominators(tree::DominatorTree) = node.(children(tree))
immediate_dominator(tree::DominatorTree) = node(@something(parent(tree), return))

DominatorTree(fdef::FunctionDefinition) = DominatorTree(control_flow_graph(fdef))
DominatorTree(cfg::AbstractGraph) = DominatorTree(dominators(cfg))

function DominatorTree(domsets::AbstractVector{Set{T}}) where {T}
  root = nothing
  idoms = Dictionary{T, T}()
  for (v, domset) in pairs(domsets)
    if length(domset) == 1
      isnothing(root) || error("Found multiple root dominators.")
      root = v
      continue
    end

    candidates = copy(domset)
    delete!(candidates, v)
    for p in candidates
      for dom in domsets[p]
        dom == p && continue
        in(dom, candidates) && delete!(candidates, dom)
      end
    end
    idom = only(candidates)
    insert!(idoms, v, idom)
  end

  root_tree = DominatorTree(DominatorNode(root))
  trees = dictionary([v => DominatorTree(DominatorNode(v)) for v in keys(idoms)])
  for (v, tree) in pairs(trees)
    idom = idoms[v]
    if isroot(tree)
      p = get(trees, idom, root_tree)
      tree = @set tree.parent = p
      trees[v] = tree
      push!(children(p), tree)
    end
  end
  root_tree
end

common_ancestor(trees) = common_ancestor(Iterators.peel(trees)...)
function common_ancestor(tree, trees)
  common_ancestor = tree
  parent_chain = parents(common_ancestor)
  for candidate in trees
    common_ancestor = find_parent(in(parent_chain), candidate)
    parent_chain = parents(common_ancestor)
    isnothing(common_ancestor) && return nothing
  end
  common_ancestor
end

is_ancestor(candidate, tree) = !isnothing(find_parent(==(candidate), tree))

function parents(tree)
  res = [tree]
  while true
    isroot(tree) && break
    tree = parent(tree)
    push!(res, tree)
  end
  res
end

function find_parent(f, tree)
  while true
    f(tree) === true && return tree
    isroot(tree) && break
    tree = parent(tree)
  end
end

traverse_cfg(fdef::FunctionDefinition) = (keys(fdef.blocks)[nodevalue(tree)] for tree in PreOrderDFS(dominance_tree(fdef)))
