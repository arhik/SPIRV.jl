struct Source
    language::SourceLanguage
    version::VersionNumber
    file::Optional{String}
    code::Optional{String}
    extensions::Vector{Symbol}
end

@broadcastref struct EntryPoint
    name::Symbol
    func::SSAValue
    model::ExecutionModel
    modes::Vector{Instruction}
    interfaces::Vector{SSAValue}
end

struct Metadata
    magic_number::UInt32
    generator_magic_number::UInt32
    version::VersionNumber
    schema::Int
end

struct LineInfo
    file::String
    line::Int
    column::Int
end

struct DebugInfo
    filenames::SSADict{String}
    names::SSADict{Symbol}
    lines::SSADict{LineInfo}
    source::Optional{Source}
end

struct Variable
    id::SSAValue
    type::SPIRType
    storage_class::StorageClass
    initializer::Optional{Instruction}
    decorations::DecorationData
end

function Variable(inst::Instruction, types::SSADict{SPIRType}, results::SSADict{Any}, decorations::SSADict{DecorationData})
    storage_class = first(inst.arguments)
    initializer = length(inst.arguments) == 2 ? results[last(inst.arguments)] : nothing
    Variable(inst.result_id, types[inst.type_id].type, storage_class, initializer, get(decorations, inst.result_id, DecorationData()))
end

SPIRType(var::Variable) = PointerType(var.storage_class, var.type)

mutable struct IR
    meta::Metadata
    capabilities::Vector{Capability}
    extensions::Vector{Symbol}
    extinst_imports::SSADict{Symbol}
    addressing_model::AddressingModel
    memory_model::MemoryModel
    entry_points::SSADict{EntryPoint}
    decorations::SSADict{DecorationData}
    types::SSADict{SPIRType}
    constants::SSADict{Instruction}
    global_vars::SSADict{Variable}
    globals::SSADict{Instruction}
    fdefs::SSADict{FunctionDefinition}
    results::SSADict{Any}
    debug::Optional{DebugInfo}
    max_ssa_id::SSAValue
end

function IR(meta::Metadata, addressing_model::AddressingModel, memory_model::MemoryModel)
    IR(meta, [], [], SSADict(), addressing_model, memory_model, SSADict(), SSADict(), SSADict(), SSADict(), SSADict(), SSADict(), SSADict(), SSADict(), nothing, 0)
end

function IR(mod::Module)
    decorations = SSADict{DecorationData}()
    member_decorations = SSADict{Dictionary{Int,DecorationData}}()
    capabilities = Capability[]
    extensions = Symbol[]
    extinst_imports = SSADict{Symbol}()
    source, memory_model, addressing_model = fill(nothing, 3)
    entry_points = SSADict{EntryPoint}()
    types = SSADict{SPIRType}()
    constants = SSADict{Instruction}()
    global_vars = SSADict{Variable}()
    globals = SSADict{Instruction}()
    fdefs = SSADict{FunctionDefinition}()
    results = SSADict{Any}()

    current_function = nothing

    # debug
    filenames = SSADict{String}()
    names = SSADict{Symbol}()
    lines = SSADict{LineInfo}()

    for (i, inst) ∈ enumerate(mod.instructions)
        (; arguments, type_id, result_id, opcode) = inst
        class, info = classes[opcode]
        @tryswitch class begin
            @case & Symbol("Mode-Setting")
                @switch opcode begin
                    @case &OpCapability
                        push!(capabilities, arguments[1])
                    @case &OpMemoryModel
                        addressing_model, memory_model = arguments
                    @case &OpEntryPoint
                        model, id, name, interfaces = arguments
                        insert!(entry_points, id, EntryPoint(Symbol(name), id, model, [], interfaces))
                    @case &OpExecutionMode || &OpExecutionModeId
                        id = arguments[1]
                        push!(entry_points[id].modes, inst)
                end
            @case & :Extension
                @switch opcode begin
                    @case &OpExtension
                        push!(extensions, Symbol(arguments[1]))
                    @case &OpExtInstImport
                        insert!(extinst_imports, result_id, Symbol(arguments[1]))
                    @case &OpExtInst
                        nothing
                end
            @case & :Debug
                @tryswitch opcode begin
                    @case &OpSource
                        language, version = arguments[1:2]
                        file, code = @match length(arguments) begin
                            2 => (nothing, nothing)
                            3 => @match arg = arguments[3] begin
                                ::Integer => (arg, nothing)
                                ::String => (nothing, arg)
                            end
                            4 => arguments[3:4]
                        end

                        if !isnothing(file)
                            file = filenames[file]
                        end
                        source = Source(language, source_version(language, version), file, code, [])
                    @case &OpSourceExtension
                        @assert !isnothing(source) "Source extension was declared before the source."
                        push!(source.extensions, Symbol(arguments[1]))
                    @case &OpName
                        id, name = arguments
                        if !isempty(name)
                            insert!(names, id, Symbol(name))
                        end
                    @case &OpMemberName
                        id, mindex, name = arguments
                        #TODO: add member name
                        nothing
                end
            @case & :Annotation
                @tryswitch opcode begin
                    @case &OpDecorate
                        id, decoration, args... = arguments
                        if haskey(decorations, id)
                            insert!(decorations[id], decoration, args)
                        else
                            insert!(decorations, id, dictionary([decoration => args]))
                        end
                    @case &OpMemberDecorate
                        id, member, decoration, args... = arguments
                        member += 1 # convert to 1-based indexing
                        insert!(get!(DecorationData, get!(Dictionary{Int,DecorationData}, member_decorations, SSAValue(id)), member), decoration, args)
                end
            @case & Symbol("Type-Declaration")
                @switch opcode begin
                    @case &OpTypeFunction
                        rettype = arguments[1]
                        argtypes = length(arguments) == 2 ? arguments[2] : SSAValue[]
                        insert!(types, result_id, FunctionType(rettype, argtypes))
                    @case _
                        insert!(types, result_id, parse_type(inst, types, results))
                end
                insert!(globals, result_id, inst)
            @case & Symbol("Constant-Creation")
                insert!(constants, result_id, inst)
                insert!(globals, result_id, inst)
            @case & Symbol("Memory")
                @tryswitch opcode begin
                    @case &OpVariable
                        storage_class = arguments[1]
                        initializer = length(arguments) == 2 ? arguments[2] : nothing
                        @switch storage_class begin
                            @case &StorageClassFunction
                                nothing
                            @case _
                                insert!(globals, result_id, inst)
                                insert!(global_vars, result_id, Variable(inst, types, results, decorations))
                        end
                end
            @case & :Function
                @tryswitch opcode begin
                    @case &OpFunction
                        control, type = arguments
                        current_function = FunctionDefinition(type, control, [], SSADict())
                        insert!(fdefs, result_id, current_function)
                    @case &OpFunctionParameter
                        push!(current_function.args, result_id)
                    @case &OpFunctionEnd
                        current_function = nothing
                end
            @case & Symbol("Control-Flow")
                @assert !isnothing(current_function)
                if opcode == OpLabel
                    insert!(current_function.blocks, inst.result_id, Block(inst.result_id, []))
                end
        end
        if !isnothing(current_function) && !isempty(current_function.blocks)
            push!(last(values(current_function.blocks)).insts, inst)
        end
        if !isnothing(result_id) && !haskey(results, result_id)
             insert!(results, result_id, inst)
        end
    end

    merge!(results, extinst_imports)

    meta = Metadata(mod.magic_number, mod.generator_magic_number, mod.version, mod.schema)
    debug = DebugInfo(filenames, names, lines, source)

    # Resolve member decoration targets to types.
    for (id, decs) in pairs(member_decorations)
        for (member, decs) in pairs(decs)
            for (dec, args) in pairs(decs)
                type = types[id]
                if type isa StructType
                    insert!(get!(DecorationData, type.member_decorations, member), dec, args)
                else
                    error("Unsupported member decoration on non-struct type $type")
                end
            end
        end
    end

    IR(meta, capabilities, extensions, extinst_imports, addressing_model, memory_model, entry_points, decorations, types, constants, global_vars, globals, fdefs, results, debug, maximum(id.(keys(results))))
end

function Module(ir::IR)
    insts = Instruction[]

    append!(insts, @inst(OpCapability(cap)) for cap in ir.capabilities)
    append!(insts, @inst(OpExtension(ext)) for ext in ir.extensions)
    append!(insts, @inst(id = OpExtInstImport(string(extinst))) for (id, extinst) in pairs(ir.extinst_imports))
    push!(insts, @inst OpMemoryModel(ir.addressing_model, ir.memory_model))
    append!(insts, @inst(OpEntryPoint(entry.model, entry.func, string(entry.name), entry.interfaces)) for entry in ir.entry_points)
    append_debug_instructions!(insts, ir)
    append_annotations!(insts, ir)
    append_globals!(insts, ir)
    append_functions!(insts, ir)

    Module(ir.meta.magic_number, ir.meta.generator_magic_number, ir.meta.version, ir.max_ssa_id.id + 1, ir.meta.schema, insts)
end

function append_debug_instructions!(insts, ir::IR)
    if !isnothing(ir.debug)
        debug::DebugInfo = ir.debug
        if !isnothing(debug.source)
            source::Source = debug.source
            args = Any[source.language, source_version(source.language, source.version)]
            !isnothing(source.file) && push!(args, source.file)
            !isnothing(source.code) && push!(args, source.code)
            push!(insts, @inst OpSource(args...))
            append!(insts, @inst(OpSourceExtension(string(ext))) for ext in source.extensions)
        end

        for (id, filename) in pairs(debug.filenames)
            push!(insts, @inst OpString(id, filename))
        end

        for (id, name) in pairs(debug.names)
            push!(insts, @inst OpName(id, string(name)))
        end
    end
end

function append_annotations!(insts, ir::IR)
    for (id, decorations) in pairs(ir.decorations)
        append!(insts, @inst(OpDecorate(id, dec, args...)) for (dec, args) in pairs(decorations))
    end
    for (id, type) in pairs(ir.types)
        if type isa StructType
            append!(insts, @inst(OpMemberDecorate(id, member - UInt32(1), dec, args...)) for (member, decs) in pairs(type.member_decorations) for (dec, args) in pairs(decs))
        end
    end
end

function append_functions!(insts, ir::IR)
    for (id, fdef) in pairs(ir.fdefs)
        append!(insts, instructions(ir, fdef, id))
    end
end

function instructions(ir::IR, fdef::FunctionDefinition, id::SSAValue)
    insts = Instruction[]
    type_id = fdef.type
    type = ir.types[type_id]
    push!(insts, @inst id = OpFunction(fdef.control, type_id)::type.rettype)
    append!(insts, @inst(id = OpFunctionParameter()::argtype) for (id, argtype) in zip(fdef.args, type.argtypes))
    append!(insts, body(fdef))
    push!(insts, @inst OpFunctionEnd())
    insts
end

function append_globals!(insts, ir::IR)
    ids = id.(collect(keys(ir.globals)))
    vals = values(ir.globals)
    perm = sortperm(ids)
    append!(insts, collect(vals)[perm])
end

function show(io::IO, mime::MIME"text/plain", ir::IR)
    mod = Module(ir)
    isnothing(ir.debug) && return show(io, mime, mod)
    str = sprint(disassemble, mod; context = :color => true)
    lines = split(str, '\n')
    filter!(lines) do line
        !contains(line, "OpName")
    end
    lines = map(lines) do line
        replace(line, r"(?<=%)\d+" => id -> string(get(ir.debug.filenames, parse(SSAValue, id), id)))
        replace(line, r"(?<=%)\d+" => id -> string(get(ir.debug.names, parse(SSAValue, id), id)))
    end
    print(io, join(lines, '\n'))
end
