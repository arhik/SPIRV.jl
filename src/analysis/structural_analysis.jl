"""
Single-entry control-flow structure which is classified according to well-specified pattern structures.
"""
@enum RegionType begin
  REGION_BLOCK
  REGION_IF_THEN
  REGION_IF_THEN_ELSE
  REGION_CASE
  REGION_TERMINATION
  REGION_PROPER
  REGION_SELF_LOOP
  REGION_WHILE_LOOP
  REGION_NATURAL_LOOP
  REGION_IMPROPER
end

"Sequence of blocks `u` ─→ [`v`, `vs...`] ─→ `w`"
REGION_BLOCK
"Conditional with one branch `u` ─→ `v` and one merge block reachable by `u` ─→ `w` or `v` ─→ `w`."
REGION_IF_THEN
"Conditional with two symmetric branches `u` ─→ `v` and `u` ─→ `w` and a single merge block reachable by `v` ─→ x or `w` ─→ x."
REGION_IF_THEN_ELSE
"Conditional with any number of symmetric branches [`u` ─→ `vᵢ`, `u` ─→ `vᵢ₊₁`, ...] and a single merge block reachable by [`vᵢ` ─→ `w`, `vᵢ₊₁` ─→ `w`, ...]."
REGION_CASE
"""
Acyclic region which contains a block `v` with multiple branches, including one or multiple branches to blocks `wᵢ` which end with a function termination instruction.
The region is composed of `v` and all the `wᵢ`.
"""
REGION_TERMINATION
"Acyclic region which does not match any other acyclic patterns."
REGION_PROPER
"Single node region which exhibits a self-loop."
REGION_SELF_LOOP
"Simple cycling region made of a condition block `u`, a loop body block `v` and a merge block `w` such that `v` ⇆ `u` ─→ `w`."
REGION_WHILE_LOOP
"Single-entry cyclic region with varying complexity such that the entry point dominates all nodes in the cyclic structure."
REGION_NATURAL_LOOP
"Single-entry region containing a multiple-entry cyclic region, such that the single entry is the least common dominator of all cycle entry nodes."
REGION_IMPROPER

# Define active patterns for use in pattern matching with MLStyle.

@active block_region(args) begin
  @when (g, v) = args begin
    start = v
    # Look ahead for a chain.
    vs = [start]
    while length(outneighbors(g, v)) == 1
      v = only(outneighbors(g, v))
      length(inneighbors(g, v)) == 1 || break
      all(!in(vs), outneighbors(g, v)) || break
      in(v, vs) && break
      push!(vs, v)
    end
    # Look behind for a chain.
    v = start
    while length(inneighbors(g, v)) == 1
      v = only(inneighbors(g, v))
      length(outneighbors(g, v)) == 1 || break
      all(!in(vs), inneighbors(g, v)) || break
      in(v, vs) && break
      pushfirst!(vs, v)
    end
    length(vs) == 1 && return
    Some(vs)
  end
end

@active self_loop(args) begin
  @when (g, v) = args begin
    in(v, outneighbors(g, v))
  end
end

@active if_then_region(args) begin
  @when (g, v) = args begin
    if length(outneighbors(g, v)) == 2
      b, c = outneighbors(g, v)
      if is_single_entry_single_exit(g, b)
        only(outneighbors(g, b)) == c && return (v, b, c)
      elseif is_single_entry_single_exit(g, c)
        only(outneighbors(g, c)) == b && return (v, c, b)
      end
    end
  end
end

@active if_then_else_region(args) begin
  @when (g, v) = args begin
    if length(outneighbors(g, v)) == 2
      b, c = outneighbors(g, v)
      if is_single_entry_single_exit(g, b) && is_single_entry_single_exit(g, c)
        d = only(outneighbors(g, b))
        d == v && return
        d == only(outneighbors(g, c)) || return
        return (v, b, c, d)
      end
    end
  end
end

@active case_region(args) begin
  @when (g, v) = args begin
    candidate = nothing
    length(outneighbors(g, v)) > 1 || return
    for w in outneighbors(g, v)
      !is_single_entry_single_exit(g, w) && return
      isnothing(candidate) && (candidate = only(outneighbors(g, w)))
      candidate == v && return
      only(outneighbors(g, w)) ≠ candidate && return
    end
    (outneighbors(g, v), candidate)
  end
end

@active termination_region(args) begin
  @when (g, v) = args begin
    length(outneighbors(g, v)) ≥ 2 || return
    termination_blocks = filter(w -> isempty(outneighbors(g, w)) && length(inneighbors(g, w)) == 1, outneighbors(g, v))
    isempty(termination_blocks) && return
    Some(termination_blocks)
  end
end

function acyclic_region(g, v, ec, doms, domtrees, backedges)
  ret = @trymatch (g, v) begin
    block_region(vs) => (REGION_BLOCK, vs)
    if_then_region(v, t, m) => (REGION_IF_THEN, [v, t])
    if_then_else_region(v, t, e, m) => (REGION_IF_THEN_ELSE, [v, t, e])
    case_region(branches, target) => (REGION_CASE, [v; branches; target])
    termination_region(termination_blocks) => (REGION_TERMINATION, [v; termination_blocks])
  end
  !isnothing(ret) && return ret
  # Possibly a proper region
  # Test that we don't have a loop or improper region.
  any(u -> in(Edge(u, v), backedges), inneighbors(g, v)) && return
  domtree = domtrees[v]
  pdom_indices = findall(children(domtree)) do tree
    w = nodevalue(tree)
    in(w, vertices(g)) && !in(w, outneighbors(g, nodevalue(domtree)))
  end
  length(pdom_indices) == 1 || return
  pdom = domtree[only(pdom_indices)]
  vs = vertices_between(v, nodevalue(pdom))
  delete!(vs, v)
  delete!(vs, nodevalue(pdom))
  (REGION_PROPER, vs)
end

@active while_loop(args) begin
  @when (g, v) = args begin
    length(inneighbors(g, v)) ≠ 2 && return
    length(outneighbors(g, v)) ≠ 2 && return
    a, b = outneighbors(g, v)
    perm = if is_single_entry_single_exit(g, a) && only(inneighbors(g, a)) == only(outneighbors(g, a)) == v
      false
    elseif is_single_entry_single_exit(g, b) && only(inneighbors(g, b)) == only(outneighbors(g, b)) == v
      true
    end
    isnothing(perm) && return
    # The returned result is of the form (loop condition, loop body, loop merge)
    perm ? (v, b, a) : (v, a, b)
  end
end

function minimal_cyclic_component(g, v, backedges)
  vs = [v]
  for w in vertices(g)
    w == v && continue
    for e in backedges
      dst(e) == v || continue
      if has_path(g, w, src(e); exclude_vertices = [v])
        push!(vs, w)
        break
      end
    end
  end
  vs
end

function cyclic_region!(sccs, g, v, ec, doms, domtrees, backedges)
  ret = @trymatch (g, v) begin
    self_loop() => (REGION_SELF_LOOP, T[])
    while_loop(cond, body, merge) => (REGION_WHILE_LOOP, [cond, body])
  end
  !isnothing(ret) && return ret

  scc = sccs[findfirst(Fix1(in, v), sccs)]
  filter!(in(vertices(g)), scc)

  length(scc) == 1 && return

  any(u -> in(Edge(u, v), ec.retreating_edges), inneighbors(g, v)) || return
  cycle = minimal_cyclic_component(g, v, backedges)
  entry_edges = filter(e -> in(dst(e), cycle) && !in(src(e), cycle), edges(g))

  if any(u -> in(Edge(u, v), backedges), inneighbors(g, v))
    # Natural loop.
    # FIXME: Return vertices in reverse post-order.
    all(==(v) ∘ dst, entry_edges) && return (REGION_NATURAL_LOOP, cycle)
  end

  # Improper region.
  length(entry_edges) < 2 && return
  # length(entry_edges) < 2 && return
  entry_points = unique!(src.(entry_edges))
  entry = common_ancestor(domtrees[v], [domtrees[ep] for ep in entry_points])
  @assert !isnothing(entry) "Multiple-entry cyclic region encountered with no single dominator"
  entry_node = node(entry)
  vs = [entry_node]
  exclude_vertices = [entry_node]
  mec_entries = unique!(dst.(entry_edges))
  for v in vertices(g)
    v == entry_node && continue
    !has_path(g, entry_node, v) && continue
    any(has_path(g, v, ep; exclude_vertices) for ep in mec_entries) && push!(vs, v)
  end
  # FIXME: Return vertices in reverse post-order (according to one possible post-order traversal).
  (REGION_IMPROPER, vs)
end

function acyclic_region(g, v)
  dfst = SpanningTreeDFS(g)
  ec = EdgeClassification(g, dfst)
  doms = dominators(g)
  bedges = backedges(g, ec, doms)
  domtree = DominatorTree(doms)
  domtrees = sort(collect(PostOrderDFS(domtree)); by = x -> node(x))
  acyclic_region(g, v, ec, doms, domtrees, bedges)
end

function cyclic_region(g, v)
  dfst = SpanningTreeDFS(g)
  ec = EdgeClassification(g, dfst)
  doms = dominators(g)
  bedges = backedges(g, ec, doms)
  domtree = DominatorTree(doms)
  domtrees = sort(collect(PostOrderDFS(domtree)); by = x -> node(x))
  sccs = strongly_connected_components(g)
  cyclic_region!(sccs, g, v, ec, doms, domtrees, bedges)
end

struct ControlNode
  index::Int
  region_type::RegionType
end

"""
Control tree.

The leaves are labeled as [`REGION_BLOCK`](@ref) regions, with the distinguishing property that they no children.

Children nodes of any given subtree are in reverse postorder according to the
original control-flow graph.
"""
const ControlTree = SimpleTree{ControlNode}

# Structures are constructed via pattern matching on the graph.

node(tree::ControlTree) = nodevalue(tree).index
region_type(tree::ControlTree) = nodevalue(tree).region_type
ControlTree(node::Integer, region_type::RegionType, children = ControlTree[]) = ControlTree(ControlNode(node, region_type), children)

is_single_entry_single_exit(g::AbstractGraph, v) = length(inneighbors(g, v)) == 1 && length(outneighbors(g, v)) == 1
is_single_entry_single_exit(g::AbstractGraph) = is_weakly_connected(g) && length(sinks(g)) == length(sources(g)) == 1

function ControlTree(cfg::AbstractGraph{T}) where {T}
  dfst = SpanningTreeDFS(cfg)
  abstract_graph = DeltaGraph(cfg)
  ec = EdgeClassification(cfg, dfst)
  doms = dominators(cfg)
  bedges = backedges(cfg, ec, doms)
  domtree = DominatorTree(doms)
  domtrees = sort(collect(PostOrderDFS(domtree)); by = x -> node(x))
  sccs = strongly_connected_components(cfg)

  control_trees = Dictionary{T, ControlTree}(copy(vertices(cfg)), ControlTree.(ControlNode.(copy(vertices(cfg)), REGION_BLOCK)))
  next = post_ordering(dfst)

  while !isempty(next)
    start = popfirst!(next)
    haskey(control_trees, start) || continue
    # `v` can change if we follow a chain of blocks in a block region which starts before `v`, or if we need to find a dominator to an improper region.
    v = start
    ret = acyclic_region(abstract_graph, v, ec, doms, domtrees, bedges)
    ret = if !isnothing(ret)
      (region_type, (v, ws...)) = ret
      (region_type, ws)
    else
      ret = cyclic_region!(sccs, abstract_graph, v, ec, doms, domtrees, bedges)
      if !isnothing(ret)
        (region_type, (v, ws...)) = ret
        (region_type, ws)
      end
    end
    isnothing(ret) && continue

    # `ws` must be in reverse post-order.
    (region_type, ws) = ret
    region = SimpleTree(ControlNode(v, region_type), control_trees[w] for w in [v; ws])

    # Add the new region and merge region vertices.
    control_trees[v] = region
    if region_type ≠ REGION_SELF_LOOP
      for w in ws
        delete!(control_trees, w)

        # Adjust back-edges and retreating edges.
        for w′ in outneighbors(abstract_graph, w)
          e = Edge(w, w′)
          if in(e, bedges)
            delete!(bedges, e)
            push!(bedges, Edge(v, dst(e)))
          end
          if in(e, ec.retreating_edges)
            delete!(ec.retreating_edges, e)
            push!(ec.retreating_edges, Edge(v, dst(e)))
          end
        end

        merge_vertices!(abstract_graph, v, w)
        rem_edge!(abstract_graph, v, v)
      end
    else
      rem_edge!(abstract_graph, v, v)
    end

    # Process transformed node next for eventual successive transformations.
    pushfirst!(next, v)
  end

  @assert nv(abstract_graph) == 1 string("Expected to contract the CFG into a single vertex, got ", nv(abstract_graph), " vertices instead.", nv(cfg) > 15 ? "" : string("\n\nShowing the remaining control trees:\n\n", join((sprintc_mime(show, tree) for (v, tree) in pairs(control_trees)), "\n\n")), "\n")
  only(control_trees)
end

function is_structured(ctree::ControlTree)
  all(PreOrderDFS(ctree)) do tree
    node = nodevalue(tree)
    !in(node.region_type, (REGION_PROPER, REGION_IMPROPER, REGION_SELF_LOOP))
  end
end

function outermost_tree(ctree::ControlTree, v::Integer)
  for subtree in PreOrderDFS(ctree)
    node(subtree) == v && return subtree
  end
end
