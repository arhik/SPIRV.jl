module SPIRV

using CEnum
using MLStyle
using Graphs
using Reexport
using Dictionaries
using AutoHashEquals
using Accessors
using ResultTypes: Result
using AbstractTrees
using AbstractTrees: parent
using SwapStreams: SwapStream
@reexport using ResultTypes: iserror, unwrap, unwrap_error

using CodeInfoTools: CodeInfoTools, finish, verify, Builder
using Core.Compiler: CodeInfo, IRCode, compute_basic_blocks, uncompressed_ir, MethodInstance, InferenceResult, typeinf, InferenceState,
  retrieve_code_info, lock_mi_inference, AbstractInterpreter, OptimizationParams, InferenceParams, get_world_counter, CodeInstance, WorldView,
  WorldRange, OverlayMethodTable
using Base.Experimental: @overlay, @MethodTable

import SPIRV_Tools_jll
const spirv_val = SPIRV_Tools_jll.spirv_val(identity)

const Optional{T} = Union{Nothing,T}

struct LiteralType{T} end
Base.:(*)(x::Number, ::Type{LiteralType{T}}) where {T} = T(x)

const U = LiteralType{UInt32}
const F = LiteralType{Float32}

const magic_number = 0x07230203
const generator_magic_number = 0x12349876

# generated SPIR-V wrapper
include("generated/enums.jl")
include("grammar.jl")
include("generated/enum_infos.jl")
include("generated/instructions.jl")
include("generated/extinsts.jl")

include("utils.jl")
include("bijection.jl")
include("cursor.jl")
include("ssa.jl")
include("instructions.jl")
include("spir_types.jl")
include("parse.jl")
include("annotated_module.jl")
include("disassemble.jl")
include("functions.jl")
include("metadata.jl")
include("ir.jl")
include("assemble.jl")
include("analysis/call_tree.jl")
include("analysis/control_flow.jl")
include("analysis/abstract_interpretation.jl")
include("analysis/data_flow.jl")
include("analysis/passes.jl")
include("validate.jl")
include("layouts.jl")
include("requirements.jl")

include("frontend/ci_cache.jl")
include("frontend/method_table.jl")
include("frontend/intrinsics.jl")
include("frontend/types/abstractarray.jl")
include("frontend/types/pointer.jl")
include("frontend/types/vector.jl")
include("frontend/types/matrix.jl")
include("frontend/types/array.jl")
include("frontend/types/image.jl")
include("frontend/intrinsics_glsl.jl")
include("frontend/vulkan.jl")
include("frontend/interpreter.jl")
include("frontend/deltagraph.jl")
include("frontend/cfg.jl")
include("frontend/reflection.jl")
include("frontend/restructuring.jl")
include("frontend/compile.jl")
include("frontend/codegen.jl")
include("frontend/shader.jl")

include("precompile.jl")

export
  # character literals
  U, F,

  # parse
  PhysicalInstruction, PhysicalModule,
  Instruction, InstructionCursor,

  # disassemble
  disassemble,

  # assemble
  assemble,

  # SPIR-V types
  SPIRType,
  VoidType,
  ScalarType, BooleanType, IntegerType, FloatType,
  VectorType, MatrixType,
  ImageType,
  SamplerType, SampledImageType,
  ArrayType,
  OpaqueType,
  StructType,
  PointerType,
  spir_type,

  # IR
  annotate, AnnotatedModule,
  IR,
  SSAValue,
  ModuleMetadata,
  SSADict,
  @inst,
  FeatureRequirements,
  FeatureSupport, AllSupported, SupportedFeatures,
  Decorations, has_decoration, decorate!, Metadata, decorations,
  set_name!,

  # CFG
  control_flow_graph,

  # validation
  validate,
  validate_shader,

  # Front-end
  CFG,
  @cfg,
  is_single_entry_single_exit,
  is_tail_structured,
  is_single_node,
  rem_head_recursion!,
  compact_reducible_bbs!,
  compact_structured_branches!,
  merge_mutually_recursive!,
  merge_return_blocks,
  compact,
  sinks,
  sources, replace_code!,
  infer, verify,
  compile,
  make_shader,
  ShaderInterface, Shader, MemoryResource,
  dependent_functions,
  LayoutStrategy, VulkanLayout, alignment,
  extract_bytes, align, aligned_size, payload_size,
  @compile,
  invalidate_all!,
  SPIRVInterpreter,
  VULKAN_METHOD_TABLE, INTRINSICS_GLSL_METHOD_TABLE, INTRINSICS_METHOD_TABLE,
  DEFAULT_CI_CACHE, VULKAN_CI_CACHE,

  # SPIR-V array/vector types
  Vec,
  Mat, @mat,
  Arr,
  Pointer,
  Image, Sampler,
  SampledImage,
  combine

end
