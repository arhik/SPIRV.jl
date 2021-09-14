module SPIRV

using CEnum
using MLStyle
using UnPack
using LightGraphs
using Reexport
using Dictionaries

const Optional{T} = Union{Nothing,T}

import Base: write, show, showerror, ==

const magic_number = 0x07230203
const ID = Int

# generated SPIR-V wrapper
include("generated/enums.jl")
include("generated/instructions.jl")

for enum ∈ [:OpCode, :Decoration]
    @eval begin
        MLStyle.is_enum(::$enum) = true
        MLStyle.pattern_uncall(e::$enum, _, _, _, _) = MLStyle.AbstractPatterns.literal(e)
    end
end

MLStyle.pattern_uncall(s::Type{Symbol}, _, _, _, _) = x -> QuoteNode(x)

include("utils.jl")
include("parse.jl")
include("disassemble.jl")
include("ssa.jl")
include("functions.jl")
include("spir_types.jl")
include("ir.jl")
include("assemble.jl")

# include("StructuredCFG/StructuredCFG.jl")
# @reexport using .StructuredCFG

export
        # parse
        PhysicalInstruction, PhysicalModule,
        Instruction,

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

        # IR
        IR,
        ID,
        Metadata,
        SSADict
end
