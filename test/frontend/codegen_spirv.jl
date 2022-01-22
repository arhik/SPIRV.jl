using SPIRV, Test
using SPIRV: OpFMul, OpFAdd

@testset "SPIR-V code generation" begin
  @testset "Straight code functions" begin
    ir = @compile f_straightcode(3.0f0)
    mod = SPIRV.Module(ir)
    @test mod ≈ parse(
      SPIRV.Module,
      """
        OpCapability(VulkanMemoryModel)
        OpExtension("SPV_KHR_vulkan_memory_model")
        OpMemoryModel(Logical, Vulkan)
   %2 = OpTypeFloat(32)
   %3 = OpTypeFunction(%2, %2)
   # Constant literals are not interpreted as floating point values.
   # Doing so would require the knowledge of types, expressed in the IR.
   %7 = OpConstant(0x3f800000)::%2
   %9 = OpConstant(0x40400000)::%2
   %4 = OpFunction(None, %3)::%2
   %5 = OpFunctionParameter()::%2
   %6 = OpLabel()
   %8 = OpFAdd(%5, %7)::%2
  %10 = OpFMul(%9, %8)::%2
  %11 = OpFMul(%10, %10)::%2
        OpReturnValue(%11)
        OpFunctionEnd()
  """,
    )
    @test !iserror(validate(ir))

    ir = @compile SPIRVInterpreter([INTRINSICS_METHOD_TABLE]) clamp(1.2, 0.0, 0.7)
    mod = SPIRV.Module(ir)
    @test mod ≈ parse(
      SPIRV.Module,
      """
        OpCapability(VulkanMemoryModel)
        OpCapability(Float64)
        OpExtension("SPV_KHR_vulkan_memory_model")
        OpMemoryModel(Logical, Vulkan)
   %2 = OpTypeFloat(64)
   %3 = OpTypeFunction(%2, %2, %2, %2)
  %10 = OpTypeBool()
   %4 = OpFunction(None, %3)::%2
   %5 = OpFunctionParameter()::%2
   %6 = OpFunctionParameter()::%2
   %7 = OpFunctionParameter()::%2
   %8 = OpLabel()
  %11 = OpFOrdLessThan(%7, %5)::%10
  %12 = OpFOrdLessThan(%5, %6)::%10
  %13 = OpSelect(%12, %6, %5)::%2
  %14 = OpSelect(%11, %7, %13)::%2
        OpReturnValue(%14)
        OpFunctionEnd()
    """,
    )
    @test !iserror(validate(ir))
  end

  @testset "Intrinsics" begin
    ir = @compile clamp(1.2, 0.0, 0.7)
    @test ir ≈ parse(
      SPIRV.Module,
      """
        OpCapability(VulkanMemoryModel)
        OpCapability(Float64)
        OpExtension("SPV_KHR_vulkan_memory_model")
   %9 = OpExtInstImport("GLSL.std.450")
        OpMemoryModel(Logical, Vulkan)
   %2 = OpTypeFloat(64)
   %3 = OpTypeFunction(%2, %2, %2, %2)
   %4 = OpFunction(None, %3)::%2
   %5 = OpFunctionParameter()::%2
   %6 = OpFunctionParameter()::%2
   %7 = OpFunctionParameter()::%2
   %8 = OpLabel()
  %10 = OpExtInst(%9, FClamp, %5, %6, %7)::%2
        OpReturnValue(%10)
        OpFunctionEnd()
    """,
    )

    ir = @compile f_extinst(3.0f0)
    mod = SPIRV.Module(ir)
    @test mod ≈ parse(
      SPIRV.Module,
      """
        OpCapability(VulkanMemoryModel)
        OpExtension("SPV_KHR_vulkan_memory_model")
   %7 = OpExtInstImport("GLSL.std.450")
        OpMemoryModel(Logical, Vulkan)
   %2 = OpTypeFloat(0x00000020)
   %3 = OpTypeFunction(%2, %2)
  %10 = OpConstant(0x40400000)::%2
  %12 = OpConstant(0x3f800000)::%2
   %4 = OpFunction(None, %3)::%2
   %5 = OpFunctionParameter()::%2
   %6 = OpLabel()
   %8 = OpExtInst(%7, Exp, %5)::%2
   %9 = OpExtInst(%7, Sin, %5)::%2
  %11 = OpFMul(%10, %9)::%2
  %13 = OpFAdd(%12, %11)::%2
  %14 = OpExtInst(%7, Log, %13)::%2
  %15 = OpFAdd(%14, %8)::%2
        OpReturnValue(%15)
        OpFunctionEnd()
    """,
    )
    @test !iserror(validate(ir))
  end

  @testset "Control flow" begin
    @testset "Branches" begin
      f_branch(x) = x > 0 ? x + 1 : x - 1
      ir = @compile f_branch(1.0f0)
      @test !iserror(validate(ir))

      function f_branches(x)
        y = clamp(x, 0, 1)
        if iszero(y)
          z = x^2
          z > 1 && return z
          x += z
        else
          x -= 1
        end
        x < 0 && return y
        x + y
      end

      ir = @compile f_branches(4.0f0)
      @test !iserror(validate(ir))
    end
  end

  @testset "Composite SPIR-V types" begin
    function unicolor(position)
      Vec(position.x, position.y, 1.0f0, 1.0f0)
    end

    ir = @compile unicolor(Vec(1.0f0, 2.0f0, 3.0f0, 4.0f0))
    @test !iserror(validate(ir))

    function store_ref(ref, x)
      ref[] += x
    end

    ir = @compile store_ref(Ref(0.0f0), 3.0f0)
    # Loading from function pointer arguments is illegal in logical addressing mode.
    @test contains(unwrap_error(validate(ir)).msg, "is not a logical pointer")
    @test iserror(validate(ir))

    struct StructWithBool
      x::Bool
      y::Int32
    end

    ir = @compile StructWithBool(::Bool, ::Int32)
    @test !iserror(validate(ir))
  end
end
