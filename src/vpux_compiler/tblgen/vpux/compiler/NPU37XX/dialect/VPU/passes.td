//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#ifndef VPUX_COMPILER_DIALECT_VPU_ARCH_37XX_PASSES
#define VPUX_COMPILER_DIALECT_VPU_ARCH_37XX_PASSES

include "mlir/Pass/PassBase.td"

//
// AdjustForOptimizedSwKernel
//

def AdjustForOptimizedSwKernel : PassBase<"adjust-for-optimized-sw-kernel", "vpux::FunctionPass"> {
    let summary = "Adjust shape or layout of SW ops to leverage optimized kernel implementation";

    let description = [{
        The pass adjusts the shape or layout of software ops to better leverage optimized SHAVE
        implementation
        Supported Optimizations:
        - Softmax:
          * Axis0: Adjust shape to leverage the optimized kernel for Softmax with axis=0
          * MultiSHAVEs: Adjust shape to gather dimensions on the tile dimension to utilize more SHAVE engines
        - Gelu & Multiply:
          * MultiSHAVEs & MultiClusters: Adjust shape to gather dimensions on the tile dimension to utilize more
          SHAVE engines and avoid Clustering strategy due to batch size
    }];

    let constructor = "vpux::VPU::arch37xx::createAdjustForOptimizedSwKernelPass()";

    let dependentDialects = [
        "vpux::VPU::VPUDialect"
    ];
}

//
// SplitRealDFTOpsPass
//

def SplitRealDFTOps : PassBase<"split-real-dft-ops", "vpux::FunctionPass"> {
    let summary = "Replace RDFT and IRDFT operations with a subgraph of smaller operations";

    let description = [{
        Replace RDFT and IRDFT operations with a subgraph of smaller operations.
        VPU.RDFT = {VPU.RDFTUncutOp->VPU.SliceOp}
        VPU.IRDFT = {VPU.IDFTOp->VPU.IRDFTLastAxisOp}
    }];

    let constructor = "vpux::VPU::arch37xx::createSplitRealDFTOpsPass()";

    let dependentDialects = [
        "vpux::VPU::VPUDialect"
    ];
}

//
// DecomposeMVN
//

def DecomposeMVN : PassBase<"decompose-mvn", "vpux::FunctionPass"> {
    let summary = "Decompose MVN into 3 separate tiled functions";

    let description = [{
        The pass can Decompose MVN into 3 separate tiled functions when can't fit into CMX.
                IN -> MVN -> OUT
            will be decompose in:
                IN -> MVN1SumOp -> MVN1MeanVarOp -> MVN1NormalizeOp -> OUT
                    \_____________________________/

        MVN1SumOp tiling will be done also in this pass. Because the current logic is to tile the output and after to back infer
        to the input. Output tensor size is NxCx2 and it can be 1x1x2, it is imposible to tile and back infer in this case.
        MVN1MeanVarOp does not need tiling because tensor is NxCx2.
        MVN1NormalizeOp will be tiled as a normal layer.
    }];

    let constructor = "vpux::VPU::arch37xx::createDecomposeMVNPass()";

    let dependentDialects = [
        "vpux::VPU::VPUDialect"
    ];
}

//
// AddProposalAuxiliaryBuffer
//

def AddProposalAuxiliaryBuffer : PassBase<"add-proposal-auxiliary-buffer", "vpux::FunctionPass"> {
    let summary = "Proposal VPU layer";

    let description = [{
        The pass is only used for NPU37XX onward, and requires the creation of a auxiliary input buffer, who has the role of storing 
        the intermediate results obtained after the relevant operation.
        The results will be sorted, recalculated, and finally, the output will be extracted based on them.
        This auxiliary buffer has a necessary size depend by input parameters.
    }];

    let constructor = "vpux::VPU::arch37xx::createAddProposalAuxiliaryBufferPass()";

    let dependentDialects = [
        "vpux::VPU::VPUDialect"
    ];
}


//
// CorrectNCEWorkloads
//

def CorrectNCEWorkloads : PassBase<"correct-NCE-workloads", "vpux::FunctionPass"> {
    let summary = "Correct NCE workloads if they do not fit requirements";

    let description = [{
        The pass adjusts workload size for NCEDepthConvolution, NCEMaxPool and NCEAveragePool,
        as well as for NCE operations that produce sparse activations.

        NCEDepthConvolutionOp, NCEMaxPoolOp and NCEAveragePoolOp require the number of channels to be 16, 32 or 64.
        If the number of channels does not match, workload is split.

        NCE operations with sparse outputs must have all variants with the same number of channels excluding the last one and the number
        of channels has to be a power of two (for VPUX37XX). Additionally, if the NCE op shares a
        consumer with another NCE op (directly or indirectly), the number of channels of their variants must be aligned.
    }];

    let constructor = "vpux::VPU::arch37xx::createCorrectNCEWorkloadsPass()";

    let dependentDialects = [
        "vpux::VPU::VPUDialect"
    ];
}

#endif
