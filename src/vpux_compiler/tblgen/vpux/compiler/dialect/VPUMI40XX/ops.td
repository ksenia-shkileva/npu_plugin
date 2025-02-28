//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#ifndef VPUX_COMPILER_DIALECT_VPUMI40XX_OPS
#define VPUX_COMPILER_DIALECT_VPUMI40XX_OPS

include "vpux/compiler/core/attributes.td"
include "vpux/compiler/core/ops_interfaces.td"
include "vpux/compiler/dialect/VPUMI40XX/dialect.td"
include "vpux/compiler/dialect/VPUMI40XX/attributes.td"
include "vpux/compiler/dialect/VPUMI40XX/ops_interfaces.td"
include "vpux/compiler/dialect/VPU/attributes.td"
include "vpux/compiler/dialect/VPU/ops_interfaces.td"
include "vpux/compiler/dialect/VPUIP/types.td"
include "vpux/compiler/dialect/VPUIP/attributes.td"
include "vpux/compiler/dialect/VPURegMapped/types.td"
include "vpux/compiler/dialect/VPURegMapped/ops_interfaces.td"

include "mlir/Dialect/Quant/QuantOpsBase.td"
include "mlir/IR/RegionKindInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//
// Base classes
//

class VPUMI40XX_Op<string mnemonic, list<Trait> traits = []> :
        Op<
            VPUMI40XX_Dialect,
            mnemonic,
            traits
        >;

class VPUMI40XX_ExecutableTaskOp<string mnemonic, list<Trait> traits = []> :
        VPUMI40XX_Op<
            mnemonic,
            !listconcat(
                traits,
                [
                    DeclareOpInterfaceMethods<DotInterface, ["getNodeColor", "printAttributes", "getEdgeDirection"]>,
                    DeclareOpInterfaceMethods<VPURegMapped_TaskOpInterface, ["supportsHardLink"]>,
                    VPUMI40XX_SingleOutputAsIndexOp
                ]
            )
        > {
}

//
// ConfigureBarrierOp
//

def VPUMI40XX_ConfigureBarrierOp :
        VPUMI40XX_Op<"ConfigureBarrier",
            [
                DeclareOpInterfaceMethods<DotInterface, ["getNodeColor", "printAttributes", "getEdgeDirection"]>,
                VPUMI40XX_SingleOutputAsIndexOp,
            ]
        > {
    let summary = "A task to configure the setup for a barrier";

    let description = [{
        dependencies here mean other barriers which contain current barrier in updateBarriers list.
    }];

    let arguments = (ins
        Variadic<VPURegMapped_IndexType>:$dependencies,
        UI8Attr:$id,
        SI64Attr:$next_same_id,
        OptionalAttr<UI8Attr>:$producer_count,
        OptionalAttr<UI8Attr>:$consumer_count,
        UnitAttr:$isFinalBarrier
    );


    let builders = [
        OpBuilder<
            (ins "VPURegMapped::IndexType":$index,
                    "int64_t":$id,
                    "int64_t":$next_same_id,
                    "mlir::IntegerAttr":$producer_count,
                    "mlir::IntegerAttr":$consumer_count)
        >,
        OpBuilder<
            (ins "VPURegMapped::IndexType":$index,
                    "int64_t":$id,
                    "int64_t":$next_same_id,
                    "mlir::IntegerAttr":$producer_count,
                    "mlir::IntegerAttr":$consumer_count,
                    "bool":$isFinalBarrier)
        >
    ];

    let results = (outs
        VPURegMapped_IndexType:$barrier
    );

    let hasVerifier = 1;

    let assemblyFormat = [{
        attr-dict
        (`(` $dependencies^ `:` type($dependencies) `)`)?
        `<` $id `,` $next_same_id `>`
        `->` type(results)
    }];
}

//
// MappedInferenceOp
//
def VPUMI40XX_MappedInferenceOp :
        VPUMI40XX_Op<"MappedInference",
            [
                DeclareOpInterfaceMethods<DotInterface, ["getNodeColor", "printAttributes", "getEdgeDirection"]>,
                VPUMI40XX_SingleOutputAsIndexOp,
                AttrSizedOperandSegments
            ]
        > {
    let summary = "Task representing the MappedInference structure";

    let arguments = (ins
        VariadicOfVariadic<VPURegMapped_IndexType, "segmentSizes">:$dmaTasks,
        DenseI32ArrayAttr:$segmentSizes,
        Variadic<VPURegMapped_IndexType>:$invariantTasks,
        Variadic<VPURegMapped_IndexType>:$variantTasks,
        Variadic<VPURegMapped_IndexType>:$actKernelRanges,
        Variadic<VPURegMapped_IndexType>:$actKernelInvocations,
        Optional<VPURegMapped_IndexType>:$mediaTasks,
        Optional<VPURegMapped_IndexType>:$barrierTasks,
        Optional<VPURegMapped_IndexType>:$workItemTasks,
        Optional<VPURegMapped_IndexType>:$bootstrapTasks,
        Optional<AnyTypeOf<[VPURegMapped_IndexType, AnyMemRef]>>:$actShaveRt,
        Variadic<AnyMemRef>:$actShaveStacks,
        Optional<MemRefOf<[UI32]>>:$dmaHwpBase,
        Optional<MemRefOf<[UI32]>>:$hwpWorkpointCfg,
        I64ArrayOfArraysAttr:$dmaCount,
        I64ArrayAttr:$invariantCount,
        I64ArrayAttr:$variantCount,
        I64ArrayAttr:$actKernelRangesCount,
        I64ArrayAttr:$actKernelInvocationsCount,
        I64Attr:$mediaCount,
        I64Attr:$barrierCount,
        OptionalAttr<I64Attr>:$workItemCount,
        OptionalAttr<I64Attr>:$bootstrapTasksCount,
        OptionalAttr<I64Attr>:$bootsrapWorkItemsCount,
        OptionalAttr<I64Attr>:$finalBarrierId
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let extraClassDeclaration = [{
        mlir::Value getListHead(VPURegMapped::TaskType, int64_t tileIdx, int64_t listIdx = 0);
        mlir::MutableOperandRange getListHeadMutable(VPURegMapped::TaskType, int64_t tileIdx, int64_t listIdx = 0);

        // TODO: E#122694 - Retrieve info needed about task counts & max tile used from OpRanges
        size_t getTaskCount(vpux::VPURegMapped::TaskType taskType, size_t tileIdx, size_t listIdx);
        size_t getMaxTaskTile(vpux::VPURegMapped::TaskType taskType);
    }];

    let assemblyFormat = [{
    attr-dict
        (`dmas` `(` $dmaTasks^ `:` type($dmaTasks) `)`)?
        (`invariants` `(` $invariantTasks^ `:` type($invariantTasks) `)`)?
        (`variants` `(` $variantTasks^ `:` type($variantTasks) `)`)?
        (`actKernelRanges` `(` $actKernelRanges^ `:` type($actKernelRanges) `)`)?
        (`actKernelInvocations` `(` $actKernelInvocations^ `:` type($actKernelInvocations) `)`)?
        (`mediaTasks` `(` $mediaTasks^ `:` type($mediaTasks) `)`)?
        (`barriers` `(` $barrierTasks^ `:` type($barrierTasks) `)` )?
        (`workItemTasks` `(` $workItemTasks^ `:` type($workItemTasks) `)` )?
        (`bootstrapTasks` `(` $bootstrapTasks^ `:` type($bootstrapTasks) `)` )?
        (`actShaveRt` `(` $actShaveRt^ `:` type($actShaveRt) `)` )?
        (`actShaveStacks` `(` $actShaveStacks^ `:` type($actShaveStacks) `)`)?
        (`dmaHwpBase` `(` $dmaHwpBase^ `:` type($dmaHwpBase) `)`)?
        (`hwpWorkpointCfg` `(` $hwpWorkpointCfg^ `:` type($hwpWorkpointCfg) `)`)?
        `dmaCount` `(` $dmaCount `)`
        `invariantCount` `(` $invariantCount `)`
        `variantCount` `(` $variantCount `)`
        `actKernelRangesCount` `(` $actKernelRangesCount `)`
        `actKernelInvocationsCount` `(` $actKernelInvocationsCount `)`
        `mediaCount` `(` $mediaCount `)`
        `barrierCount` `(` $barrierCount `)`
        (`workItemCount` `(` $workItemCount^ `)`)?
        (`bootstrapTasksCount` `(` $bootstrapTasksCount^ `)`)?
        (`bootsrapWorkItemsCount` `(` $bootsrapWorkItemsCount^ `)`)?
        (`finalBarrierId` `(` $finalBarrierId^ `)`)?
        `->` type(results)
    }];
}


//
// NNDMAOp
//

def VPUMI40XX_NNDMAOp :
        VPUMI40XX_ExecutableTaskOp<"NNDMA",
            [
                DeclareOpInterfaceMethods<VPUMI40XX_ExecutableTaskOpInterface>,
                AttrSizedOperandSegments
            ]
        > {
    let summary = "NN DMA task";

    let arguments = (ins
        Optional<VPURegMapped_IndexType>:$taskLocation,
        AnyMemRef:$input,
        Variadic<AnyMemRef>:$output_buffs,
        Optional<VPURegMapped_IndexType>:$previousTask,
        Variadic<VPURegMapped_IndexType>:$waitBarriers,
        Variadic<VPURegMapped_IndexType>:$updateBarriers,
        UI64Attr:$start_after,
        UI64Attr:$clean_after,
        UnitAttr:$is_out_of_order,
        UnitAttr:$is_critical,
        UnitAttr:$enable_msc,
        IntAttr:$port,
        VPUIP_DMAAccModeAttr:$acceleration_mode,
        Optional<AnyMemRef>:$act_compression_size_entry,
        Optional<AnyMemRef>:$act_compression_sparsity_map,
        OptionalAttr<VPUMI40XX_DMATransactionAttr>:$dma_transaction,
        OptionalAttr<VPUIP_DMADescriptorAttr>:$dma_descriptor,
        OptionalAttr<IntAttr>:$dma_hwp_id,
        OptionalAttr<VPUIP_DmaProfilingMetadataAttr>:$profilingMetadata,
        UnitAttr:$allow_different_in_out_shapes,
        Optional<AnyMemRef>:$indices
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let builders = [
        OpBuilder<
            (ins "mlir::Value":$src, "mlir::Value":$dst)
        >,
        OpBuilder<
            (ins "VPURegMapped::IndexType":$index,
                    "mlir::Value":$taskLocation,
                    "mlir::Value":$input,
                    "mlir::Value":$output_buff,
                    "mlir::Value":$prevousDma,
                    "mlir::ValueRange":$waitBarriers,
                    "mlir::ValueRange":$updateBarriers,
                    "VPUMI40XX::DMATransactionAttr":$dma_transaction,
                    "VPUIP::DMADescriptorAttr":$dma_descriptor)
        >
    ];

    let hasVerifier = 1;

    let extraClassDefinition = [{
        vpux::VPURegMapped::TaskType vpux::VPUMI40XX::NNDMAOp::getTaskType() {
            return vpux::VPURegMapped::TaskType::DMA;
        }
    }];

    let assemblyFormat = [{
        attr-dict
        (`taskLocation` `(` $taskLocation^ `:` type($taskLocation) `)`)?
        `inputs` `(` $input `:` type($input) `)`
        (`outputs` `(` $output_buffs^ `:` type($output_buffs) `)`)?
        ( `previousDMA` `(` $previousTask^ `:` type($previousTask) `)`)?
        (`waits` `(` $waitBarriers^ `:` type($waitBarriers) `)`)?
        (`updates` `(` $updateBarriers^ `:` type($updateBarriers) `)`)?
        `start_after` `(` $start_after `)`
        `clean_after` `(` $clean_after `)`
        `acceleration_mode` `(` $acceleration_mode `)`
        (`dma_transaction` `(` $dma_transaction^ `)`)?
        (`act_compression_size_entry` `(` $act_compression_size_entry^  `:` type($act_compression_size_entry) `)`)?
        (`act_compression_sparsity_map` `(` $act_compression_sparsity_map^  `:` type($act_compression_sparsity_map) `)`)?
        (`dma_hwp_id` `(` $dma_hwp_id^ `)`)?
        (`indices` `(` $indices^ `:` type($indices) `)`)?
        `->` type(results)
    }];

    let hasVerifier = 1;

}

//
// Activation Kernel Ops
//

//
// ActShaveRtOp
//

def VPUMI40XX_ActShaveRtOp :
        VPUMI40XX_Op<"ActShaveRt",
            [
                VPUMI40XX_SingleOutputAsIndexOp,
                DeclarationOp
            ]
        > {
    let summary = "Declaration of Act Shave Management Kernel";

    let arguments = (ins
        StrAttr:$kernel_path
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict `kernel` `(` $kernel_path `)` `->` type(results)
    }];

}

//
// DeclareKernelTextOp
//

def VPUMI40XX_DeclareKernelTextOp :
        VPUMI40XX_Op<"DeclareKernelText",
            [
                VPUMI40XX_SingleOutputAsIndexOp,
                DeclarationOp
            ]
        > {
    let summary = "Declaration of Software Kernel .text ";

    let arguments = (ins
        StrAttr:$kernel_path
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict `kernel_path` `(` $kernel_path `)` `->` type(results)
    }];
}


//
// DeclareKernelArgsOp
//

def VPUMI40XX_DeclareKernelArgsOp :
        VPUMI40XX_Op<"DeclareKernelArgs",
            [
                VPUMI40XX_SingleOutputAsIndexOp,
                DeclarationOp
            ]
        > {
    let summary = "Declaration of Software Kernel .args";

    let arguments = (ins
        StrAttr:$kernel_path
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict `kernel_path` `(` $kernel_path `)` `->` type(results)
    }];
}

//
// DeclareKernelEntryOp
//

def VPUMI40XX_DeclareKernelEntryOp :
        VPUMI40XX_Op<"DeclareKernelEntry",
            [
                VPUMI40XX_SingleOutputAsIndexOp,
                DeclarationOp
            ]
        > {
    let summary = "Declaration of Kernel Entry";

    let arguments = (ins
        StrAttr:$kernel_path
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict `kernel_path` `(` $kernel_path `)` `->` type(results)
    }];

}

//
// KernelParamsOp
//

def VPUMI40XX_KernelParamsOp :
        VPUMI40XX_Op<"KernelParams",
            [
                VPUMI40XX_SingleOutputAsIndexOp,
                AttrSizedOperandSegments
            ]
        > {
    let summary = "Kernel Params";

    let description = [{
        This operation contains description of parameters for software kernel, accommodating both dynamic and static shapes. 
        For dynamic shapes, the parameters `dynamicInputShapes` and `dynamicOutputShapes` are utilized. 
        If a shape does not need to be dynamic, the corresponding parameter can be omitted. The shape is resolved via kernel_params for this case.

        Currently, support for dynamic shapes is limited to scenarios with a single input or output.
        The rank of these shapes is inferred from the bounds and layout; dynamic rank is not supported.

        For instance, consider a ReLu operation with the following specifications:
        - Input: `tensor<1x?x?xf32>, {bounds = [1, 18, 15], order = #CHW}`
        - Output: `tensor<1x?x?xf32>, {bounds = [1, 18, 15], order = #CHW}`
        In this example, the dimensions are defined by the layout and bounds. Consequently, the input will allocate a buffer with memref<1x18x15xf32>, order = #CHW. 
        
        In the VPUMI40XX dialect, the arguments are defined as follows:
        | Arguments              | Type                | Description                                                                                                                                                                                                 |
        |------------------------|-------------------  |-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
        | inputs                 | memref<1x18x15xf16> | Collection of static shapes (or upper bounds) of inputs/outputs.                                                                                                                                              |
        | outputs                | memref<1x18x15xf16> |                                                                                                                                                                                                             |
        | dynamicInputShapes     | memref<3xsi32>      | Collection of dynamic shapes of inputs/outputs. The dimension value in the dynamic shape represents the size available at runtime and cannot be larger than the corresponding upper bound. The dynamic shape contains the whole shape, including both static and dynamic dimensions (its rank is equal to the rank of the corresponding input/output static shape).                                                      | 
        | dynamicOutputShapes    | memref<3xsi32>      |                                                                                                                                                                                                             |
        | dynamicInputShapesSize | array<i32: 1>       | Amount of inputs/outputs processed by the kernel. In this case, it is an array that contains a single integer and the value is 1. Adding the sizes is a requirement of MLIR framework. For more details, please refer to [MLIR documentation on defining dialects and operations](https://mlir.llvm.org/docs/DefiningDialects/Operations/#variadicofvariadic-operands).               |
        | dynamicOutputShapesSize| array<i32: 1>       |                                                                                                                                                                                                             |
    }];

    let arguments = (ins
        Variadic<AnyMemRef>:$inputs,
        Variadic<AnyMemRef>:$outputs,
        VariadicOfVariadic<AnyMemRef, "dynamicInputShapesSize">:$dynamicInputShapes,
        VariadicOfVariadic<AnyMemRef, "dynamicOutputShapesSize">:$dynamicOutputShapes,
        DenseI32ArrayAttr:$dynamicInputShapesSize,
        DenseI32ArrayAttr:$dynamicOutputShapesSize,
        StrAttr:$kernel_type,
        ElementsAttr:$kernel_params
    );

    let results = (outs
        VPURegMapped_IndexType:$index  // TODO: modify to VPUIndexType
    );

    let assemblyFormat = [{
        attr-dict
        `inputs` `(` $inputs `:` type($inputs) `)`
        `outputs` `(` $outputs `:` type($outputs) `)`
        (`dynamicInputShapes` `(` $dynamicInputShapes^ `:` type($dynamicInputShapes) `)`)?
        (`dynamicOutputShapes` `(` $dynamicOutputShapes^ `:` type($dynamicOutputShapes) `)`)?
        `kernel_type` `(` $kernel_type `)`
        `kernel_params` `(` $kernel_params `)`
        `->` type(results)
    }];
}

//
// ActKernelRangeOp
//

def VPUMI40XX_ActKernelRangeOp : VPUMI40XX_ExecutableTaskOp<"ActKernelRange",
        [
            AttrSizedOperandSegments
        ]> {
    let summary = "Activation Kernel Range";

    let arguments = (ins
        Optional<VPURegMapped_IndexType>:$taskLocation,
        Optional<VPURegMapped_IndexType>:$previousTask,
        Optional<VPURegMapped_IndexType>:$kernel_text_index,
        Optional<VPURegMapped_IndexType>:$kernel_args_index,
        Optional<VPURegMapped_IndexType>:$kernel_entry_index,
        SymbolRefAttr:$kernelTaskType
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let extraClassDefinition = [{
        vpux::VPURegMapped::TaskType vpux::VPUMI40XX::ActKernelRangeOp::getTaskType() {
            return vpux::VPURegMapped::TaskType::ActKernelRange;
        }
    }];

    let assemblyFormat = [{
        attr-dict
        (`taskLocation` `(` $taskLocation^ `:` type($taskLocation) `)`)?
        ( `previousTask` `(` $previousTask^ `:` type($previousTask) `)`)?
        (`kernel_text_index` `(` $kernel_text_index^ `:` type($kernel_text_index) `)`)?
        (`kernel_args_index` `(` $kernel_args_index^ `:` type($kernel_args_index) `)`)?
        (`kernel_entry_index` `(` $kernel_entry_index^ `:` type($kernel_entry_index) `)`)?
        `kernelTaskType` `(` $kernelTaskType `)`
        `->` type(results)
    }];
}

//
// ActKernelInvocationOp
//

def VPUMI40XX_ActKernelInvocationOp :
        VPUMI40XX_ExecutableTaskOp<"ActKernelInvocation",
            [
                DeclareOpInterfaceMethods<VPUMI40XX_ExecutableTaskOpInterface>,
                AttrSizedOperandSegments
            ]
        > {
    let summary = "Activation Kernel Invocation";

    let arguments = (ins
        Optional<VPURegMapped_IndexType>:$taskLocation,
        Optional<VPURegMapped_IndexType>:$previousTask,
        Variadic<VPURegMapped_IndexType>:$waitBarriers,
        Variadic<VPURegMapped_IndexType>:$updateBarriers,
        VPURegMapped_IndexType:$range_index,
        VPURegMapped_IndexType:$kernel_params,
        Optional<MemRefOf<[UI32]>>:$profiling_data,
        DefaultValuedAttr<UI64Attr, "0">:$tile,
        UI64Attr:$start_after,
        UI64Attr:$clean_after,
        OptionalAttr<VPUIP_SwProfilingMetadataAttr>:$profilingMetadata
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let hasVerifier = 1;

    let extraClassDefinition = [{
        vpux::VPURegMapped::TaskType vpux::VPUMI40XX::ActKernelInvocationOp::getTaskType() {
            return vpux::VPURegMapped::TaskType::ActKernelInvocation;
        }
    }];

    let assemblyFormat = [{
        attr-dict
        (`taskLocation` `(` $taskLocation^ `:` type($taskLocation) `)`)?
        ( `previousTask` `(` $previousTask^ `:` type($previousTask) `)`)?
        `range_index` `(` $range_index `:` type($range_index) `)`
        `kernel_params` `(` $kernel_params `:` type($kernel_params) `)`
        (`profiling_data` `(` $profiling_data^ `:` type($profiling_data) `)`)?
        (`waits` `(` $waitBarriers^ `:` type($waitBarriers) `)`)?
        (`updates` `(` $updateBarriers^ `:` type($updateBarriers) `)`)?
        `tile` `(` $tile `)`
        `start_after` `(` $start_after `)`
        `clean_after` `(` $clean_after `)`
        `->` type(results)
    }];
}

//
// DPU Variant Op
//

def VPUMI40XX_DPUVariantOp :
        VPUMI40XX_ExecutableTaskOp<"DPUVariant",
            [
                AttrSizedOperandSegments
            ]
        > {

    let summary = "DPU Variant Op";

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let arguments = (ins
        Optional<VPURegMapped_IndexType>:$taskLocation,
        Optional<VPURegMapped_IndexType>:$previousTask,
        VPURegMapped_IndexType:$Invariant,
        Optional<MemRefOf<[F16, BF16, quant_QuantizedType]>>:$weights,
        Optional<MemRefOf<[SI32]>>:$weight_table,
        VPUIP_NCETaskTypeAttr:$nce_task_type,
        I64ArrayAttr:$inStart,
        I64ArrayAttr:$inEnd,
        I64ArrayAttr:$start,
        I64ArrayAttr:$end,
        VPU_PaddingAttr:$pad,
        VPU_MPEModeAttr:$mpe_mode,
        DefaultValuedAttr<UI64Attr, "0">:$cluster_id,
        OptionalAttr<DPUHaloRegionArrayAttr>: $haloRegions,
        OptionalAttr<IntAttr>:$workload_id,
        UnitAttr:$lut_read
    );

    let extraClassDefinition = [{
        vpux::VPURegMapped::TaskType vpux::VPUMI40XX::DPUVariantOp::getTaskType() {
            return vpux::VPURegMapped::TaskType::DPUVariant;
        }
    }];

    let assemblyFormat = [{
        (`taskLocation` `(` $taskLocation^ `:` type($taskLocation) `)`)?
        ( `previousTask` `(` $previousTask^ `:` type($previousTask) `)`)?
        `calls` `(` $Invariant `:` type($Invariant) `)`
        (`weights` `(` $weights^ `:` type($weights) `)`)?
        (`weight_table` `(` $weight_table^ `:` type($weight_table) `)`)?
        attr-dict
        `->` type($index)
    }];
}

def VPUMI40XX_PPETaskOp : VPU_PPETaskOpBase<
    VPUMI40XX_Dialect,
    "PPETask",
    [HasParent<"vpux::VPUMI40XX::DPUInvariantOp">]
> {}

//
// DPU Invariant Op
//

def VPUMI40XX_DPUInvariantOp :
        VPUMI40XX_ExecutableTaskOp<"DPUInvariant",
            [
                DeclareOpInterfaceMethods<VPUMI40XX_ExecutableTaskOpInterface>,
                AttrSizedOperandSegments
            ]
            # GraphRegionNoTerminator.traits
        > {

    let summary = "DPU Invariant Op";

    let arguments = (ins
        Optional<VPURegMapped_IndexType>:$taskLocation,
        Optional<VPURegMapped_IndexType>:$previousTask,
        MemRefOf<[F16, BF16, quant_QuantizedType]>:$input,
        Optional<MemRefOf<[I1]>>:$input_sparsity_map,
        Optional<MemRefOf<[I32]>>:$input_storage_element_table,
        Optional<MemRefOf<[F16, BF16, quant_QuantizedType]>>:$weights,
        Optional<MemRefOf<[I1]>>:$weights_sparsity_map,
        Optional<MemRefOf<[SI32]>>:$weight_table,
        Optional<MemRefOf<[UI16]>>:$spr_lookup_table,

        Variadic<MemRefOf<[F16, F32, BF16, quant_QuantizedType]>>:$output_buffs,
        Variadic<MemRefOf<[I1]>>:$output_sparsity_map_buffs,
        Optional<MemRefOf<[UI64]>>:$profiling_data,

        VPUIP_NCETaskTypeAttr:$nce_task_type,
        VPU_MPEModeAttr:$mpe_frequent_mode,

        OptionalAttr<I64ArrayAttr>:$kernel_size,
        OptionalAttr<I64ArrayAttr>:$kernel_strides,
        OptionalAttr<VPU_PaddingAttr>:$kernel_padding,
        OptionalAttr<IntAttr>:$activation_window_channel_length,
        UnitAttr:$is_continued,
        OptionalAttr<IntAttr>:$cm_sp_pattern,
        UnitAttr:$input_channels_compression,
        OptionalAttr<IntAttr>:$out_channel_offset,
        UnitAttr:$is_superdense,
        OptionalAttr<BoolAttr>:$is_inplace,
        OptionalAttr<IntAttr>:$input_se_size,
        OptionalAttr<IntAttr>:$output_se_size,
        UnitAttr:$is_permute_quantize,
        UnitAttr:$is_small_kernel_optimized,
        OptionalAttr<VPUIP_DpuProfilingMetadataAttr>:$profilingMetadata,

        Variadic<VPURegMapped_IndexType>:$waitBarriers,
        Variadic<VPURegMapped_IndexType>:$updateBarriers,
        UI64Attr:$start_after,
        UI64Attr:$clean_after
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let regions = (region
        SizedRegion<1>:$ppe
    );

    let hasVerifier = 1;

    let extraClassDeclaration = [{
        std::size_t getBarrierHitsCount() {
            auto users = getResult().getUsers();
            return static_cast<std::size_t>(std::count_if(std::begin(users), std::end(users), [](auto user) { return mlir::isa<vpux::VPUMI40XX::DPUVariantOp>(user); }));
        }
    }];

    let extraClassDefinition = [{
        vpux::VPURegMapped::TaskType vpux::VPUMI40XX::DPUInvariantOp::getTaskType() {
            return vpux::VPURegMapped::TaskType::DPUInvariant;
        }
    }];

    let assemblyFormat = [{
        attr-dict
        (`taskLocation` `(` $taskLocation^ `:` type($taskLocation) `)`)?
        ( `previousTask` `(` $previousTask^ `:` type($previousTask) `)`)?
        `input` `(` $input `:` type($input) `)`
        (`input_sparsity_map` `(` $input_sparsity_map^ `:` type($input_sparsity_map) `)`)?
        (`input_storage_element_table` `(` $input_storage_element_table^ `:` type($input_storage_element_table) `)`)?
        (`weights` `(` $weights^  `:` type($weights) `)`)?
        (`weights_sparsity_map` `(` $weights_sparsity_map^ `:` type($weights_sparsity_map) `)`)?
        (`weight_table` `(` $weight_table^ `:` type($weight_table) `)`)?
        (`spr_lookup_table` `(` $spr_lookup_table^ `:` type($spr_lookup_table) `)`)?
        (`outputs` `(` $output_buffs^ `:` type($output_buffs) `)`)?
        (`output_sparsity_maps` `(` $output_sparsity_map_buffs^ `:` type($output_sparsity_map_buffs) `)`)?
        (`profiling_data` `(` $profiling_data^ `:` type($profiling_data) `)`)?
        (`waits` `(` $waitBarriers^ `:` type($waitBarriers) `)`)?
        (`updates` `(` $updateBarriers^ `:` type($updateBarriers) `)`)?
        `->` type($index)
        `PPE` `:` $ppe
    }];

}

//
// Network Metadtata Op
//

def VPUMI40XX_NetworkMetadataOp :
        VPUMI40XX_Op<"NetworkMetadata", []> {
    let summary = "Network Metadata Op";

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict `->` type(results)
    }];
}

//
// Profiling Metadata Op
//

def VPUMI40XX_ProfilingMetadataOp :
        VPUMI40XX_Op<"ProfilingMetadata", []> {
    let summary = "Profiling Metadata Op (with metadata included as attribute intended to store it in binary form)";

    let arguments = (ins
        ElementsAttr:$metadata
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict `->` type(results)
    }];
}

//
// M2IOp
//

def VPUMI40XX_M2IOp :
        VPUMI40XX_ExecutableTaskOp<"M2I",
            [
                DeclareOpInterfaceMethods<VPUMI40XX_ExecutableTaskOpInterface>,
                AttrSizedOperandSegments
            ]
        > {
    let summary = "M2I task op";

    let arguments = (ins
        Optional<VPURegMapped_IndexType>:$taskLocation,
        Optional<VPURegMapped_IndexType>:$previousTask,
        MemRefOf<[UI8, F16]>:$input,
        MemRefOf<[UI8, F16]>:$output_buff,
        Optional<MemRefOf<[UI8]>>:$profiling_data,

        UnitAttr:$do_csc,
        UnitAttr:$do_norm,
        VPU_M2iColorFmtAttr:$inFmt,
        VPU_M2iColorFmtAttr:$outFmt,
        UnitAttr:$chroma_in_reverse_channels,
        UnitAttr:$chroma_out_reverse_channels,
        UnitAttr:$luma_in_reverse_channels,
        UnitAttr:$luma_out_reverse_channels,
        UI32Attr:$scale_factor_x,
        UI32Attr:$scale_factor_y,
        OptionalAttr<F64ArrayAttr>:$norm,
        OptionalAttr<UI32Attr>:$tile_offset_x,
        OptionalAttr<UI32Attr>:$tile_offset_y,
        OptionalAttr<VPUIP_M2IProfilingMetadataAttr>:$profilingMetadata,
        DefaultValuedAttr<VPU_M2iInterpAttr, "vpux::VPU::M2iInterp::NEAREST">:$interp,

        Variadic<VPURegMapped_IndexType>:$waitBarriers,
        Variadic<VPURegMapped_IndexType>:$updateBarriers,
        UI64Attr:$start_after,
        UI64Attr:$clean_after
    );

    let results = (outs
        VPURegMapped_IndexType:$index
    );

    let assemblyFormat = [{
        attr-dict
        (`taskLocation` `(` $taskLocation^ `:` type($taskLocation) `)`)?
        (`previousTask` `(` $previousTask^ `:` type($previousTask) `)`)?
        `inputs` `(` $input `:` type($input) `)`
        `outputs` `(` $output_buff `:` type($output_buff) `)`
        (`profiling_data` `(` $profiling_data^ `:` type($profiling_data) `)`)?
        (`waits` `(` $waitBarriers^ `:` type($waitBarriers) `)`)?
        (`updates` `(` $updateBarriers^ `:` type($updateBarriers) `)`)?
        `->` type(results)
    }];

    let extraClassDefinition = [{
        vpux::VPURegMapped::TaskType vpux::VPUMI40XX::M2IOp::getTaskType() {
            return vpux::VPURegMapped::TaskType::M2I;
        }
    }];
}

//
// BootstrapOp
//

def VPUMI40XX_BootstrapOp :
        VPUMI40XX_Op<"Bootstrap",
            [
                VPUMI40XX_SingleOutputAsIndexOp,
                DeclarationOp
            ]
        > {
    let summary = "Each BootstrapOp associated with barrier. The goal of this list of tasks - allow runtime start barriers in non-fixed";

    let arguments = (ins
        VPURegMapped_IndexType:$barrier
    );

    let results = (outs
        VPURegMapped_IndexType:$bootstrap
    );

    let hasVerifier = 1;

    let assemblyFormat = [{
        attr-dict
        `inputs` `(` $barrier `:` type($barrier) `)`
        `->` type(results)
    }];
}

//
// OpRanges
//

def OpRanges : VPUMI40XX_Op<"OpRanges", [
    Pure,
    HasParent<"mlir::func::FuncOp">,
    Terminator,
    SameVariadicOperandSize
]> {
    let summary = "Tasks ranges lists to be used for IR navigation";
    let description = [{
        OpRanges represents a list of "task ranges" presented in the IR. Task range is
        something that can be used to iterate over IR to access task operations
        of specific type in a given Mapped Inference list.

        Examples of Mapped Inference task lists: DMA ops for engine 0 from CMX
        (list 1), DMA ops for engine 0 from DDR (list 0), DPU Invariants for
        tile 0 and etc.

        Range is represented as [begin..end] pair of VPURegMapped::IndexType
        stored in `begins` and `ends` lists accordingly. Type of the range is
        identified by corresponding (entry with the same index)
        VPURegMapped::TaskTypeAttr from `types` list.

        It's expected all tasks that are part of a range have the same tile and
        list component of VPURegMapped::IndexType and value component is
        monotonously non-decreasing from begin to end.

        Only ranges from the start of a list are supported. No duplicates of a range
        (the same task type, tile and list indexes) are allowed.
    }];

    let arguments = (ins
        Variadic<VPURegMapped_IndexType>:$begins,
        Variadic<VPURegMapped_IndexType>:$ends,
        // Use DefaultValuedAttr to make printer generate nothing in case of empty OpRanges
        // Empty OpRanges can be encountered in specific LIT tests, but usually not expected
        // for a model
        DefaultValuedAttr<ArrayAttr, "{}">:$types
    );

    let assemblyFormat = [{
        (`types` `(` $types^ `)`)?
        (`begins` `(` $begins^ `:` type($begins) `)`)?
        (`ends` `(` $ends^ `:` type($ends) `)`)?
        attr-dict
    }];

    let extraClassDeclaration = [{
        ::vpux::VPUMI40XX::TaskForwardRange getForwardRange(::vpux::VPURegMapped::TaskType, ::vpux::VPURegMapped::IndexType);
        ::vpux::VPUMI40XX::TaskBackwardRange getBackwardRange(::vpux::VPURegMapped::TaskType, ::vpux::VPURegMapped::IndexType);
    }];

    let hasVerifier = 1;
}

#endif
