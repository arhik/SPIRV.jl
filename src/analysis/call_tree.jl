struct StaticCallTree
  ir::IR
  root::SSAValue
end

AbstractTrees.ChildIndexing(::Type{StaticCallTree}) = IndexedChildren()
AbstractTrees.rootindex(call_tree::StaticCallTree) = call_tree.root

Base.getindex(call_tree::StaticCallTree, index::SSAValue) = call_tree.ir.fdefs[index]

function AbstractTrees.childindices(call_tree::StaticCallTree, index::SSAValue)
  children = Set{SSAValue}()
  fdef = call_tree[index]
  for blk in fdef.blocks
    for inst in blk
      if inst.opcode == OpFunctionCall
        fid = inst.arguments[1]::SSAValue
        if haskey(call_tree.ir.fdefs, fid)
          push!(children, fid)
        else
          # For a valid module, the called function must have been imported from another SPIR-V module.
          error("Not implemented")
        end
      end
    end
  end
  children
end

function dependent_functions(ir::IR, fid::SSAValue)
  haskey(ir.fdefs, fid) || error("SSA value $fid is not a known function.")
  unique(nodevalue(node) for node in PreOrderDFS(IndexNode(StaticCallTree(ir, fid))))
end

struct Frame
  ir::IR
  fid::SSAValue
  block::SSAValue
  instruction_index::Int
  parent_frames::Vector{Frame}
end

Frame(ir::IR, fid::SSAValue, parent_frames = Frame[]) = Frame(ir, fid, first(keys(ir.fdefs[fid])), 1, parent_frames)

AbstractTrees.NodeType(::Type{Frame}) = Frame
AbstractTrees.ChildIndexing(::Type{Frame}) = IndexedChildren()

function AbstractTrees.children(frame::Frame)
  fdef = frame.ir.fdefs[frame.fid]
  inst = fdef[frame.block][frame.instruction_index]
  parent_frames = [frame.parent_frames; frame]

  # traverse_cfg(fdef)
  # if inst.opcode == OpFunctionCall
  #   (Frame(frame.ir, first(inst.arguments)::SSAValue, parent_frames))
  # end
end
