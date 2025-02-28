//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU40XX/dialect/VPU/transforms/passes.hpp"
#include "vpux/compiler/core/passes.hpp"

#include "vpux/compiler/utils/rewriter.hpp"

#include <mlir/Pass/PassManager.h>
#include <mlir/Transforms/Passes.h>

using namespace vpux;

void vpux::VPU::arch40xx::buildIncrementalPipeline(mlir::OpPassManager& pm, const vpux::MCAndTilingOptionsBase& options,
                                                   Logger log) {
    pm.addPass(VPU::arch37xx::createDecomposeMVNPass(log));

    pm.addPass(VPU::createMultiClusterStrategyAssignmentPass(options.enablePrefetching, log));

    pm.addPass(VPU::createManualStrategyUtilsPass(options.writeStrategyToJson, writeStrategyFileLocation,
                                                  options.readStrategyFromJson, readStrategyFileLocation, log));
    pm.addPass(VPU::createSplitGRUSequencePass(log));

    VPU::buildTilingPipeline(pm, VPU::TilingOptions(options), log);

    pm.addPass(VPU::createComputeInterpolateCoordinatesPass(log));
    pm.addPass(VPU::createRemoveOutputSparseToAvoidSuboptimalDPUWorkloadsPass(log));

    pm.addPass(VPU::createMakeOpsWithDistributedTensorPass(options.enableExplicitDistributedTensorAttr, log));
    pm.addPass(VPU::createAdjustDistributedTensorAroundOpsPass(log));
    pm.addPass(VPU::createWrapDistributedOpsInNCEClusterTiling(log));
}

//
// DefaultHWPipeline
//

void vpux::VPU::arch40xx::buildDefaultHWPipeline(mlir::OpPassManager& pm,
                                                 const VPU::arch40xx::DefaultHWOptions& options, Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();

    pm.addPass(VPU::createTileGatherPass(log));
    pm.addPass(VPU::createConvertOpToDMAForPerformantExecutionPass(log));
    pm.addPass(VPU::arch40xx::createMoveConvertAroundViewLikeOpsPass(log));
    pm.addPass(VPU::arch37xx::createAdjustForOptimizedSwKernelPass(log));
    pm.addPass(VPU::createDetectionOutputDecompositionPass(log));
    pm.addPass(VPU::arch37xx::createSplitRealDFTOpsPass(log));
    pm.addPass(VPU::arch37xx::createAddProposalAuxiliaryBufferPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));

    if (options.enableSEPtrsOperations || options.enableExperimentalSEPtrsOperations) {
        pm.addPass(VPU::createSplitSEOpsPass(
                /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
                /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
        pm.addPass(VPU::createLowerOpsToSENCEPass(
                /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
                /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
    }

    pm.addPass(VPU::createSetupPPEPass(log));
    pm.addPass(VPU::createFuseClampPass(log));

    pm.addPass(VPU::createEnsureNCEOpsSizeRequirementsPass(log));

    if (options.enableWeightsSparsity) {
        VPU::buildWeightsSparsityPipeline(pm, VPU::WeightsSparsityOptions(options), log);
    }
    pm.addPass(VPU::createAddExplicitPaddingBeforeNCEPermutePass(log));
    if (VPU::isActSparsityEnabled(options.enableActivationSparsity)) {
        VPU::buildActivationSparsityPipeline(pm, VPU::ActivationSparsityOptions(options), log);
        pm.addPass(VPU::createLowerSparsityOpsPass(/*fakeSparsify=*/false, log));
    }

    if (options.enableInPlaceEltwise) {
        pm.addPass(VPU::createDetectInPlaceEltwisePass(log));
    }

    if (options.enableM2I) {
        pm.addPass(VPU::arch40xx::createFuseM2IOpsPass(log));
        pm.addPass(VPU::arch40xx::createConvertM2IOpsPass(log));
    }

    if (options.enableSMPipeline) {
        VPU::buildSMPipeline(pm, vpux::MCAndTilingOptionsBase(options), log);
    } else {
        VPU::arch40xx::buildIncrementalPipeline(pm, vpux::MCAndTilingOptionsBase(options), log);
    }

    pm.addPass(VPU::createOptimizeSharedInputCopyForConcatPass(log));
    pm.addPass(VPU::createOptimizeConcatPass(log));
    pm.addPass(VPU::createAdjustMemorySpacePass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(VPU::createCMXConcatPass(log, options.supportNCEOpInsertion));
    pm.addPass(mlir::createCanonicalizerPass(grc));

    pm.addPass(VPU::createSplitNCEOpsOntoWorkloadsPass(log));
    pm.addPass(VPU::arch40xx::createCorrectNCEWorkloadsPass(log));
    pm.addPass(VPU::createResolveEltwiseWithZTiledWorkloadsPass(log));
    pm.addPass(VPU::arch40xx::createComputeNCEInputWorkloadsPass(log));
    pm.addPass(VPU::createShiftOutputWorkloadsForHaloPass(log));
}

void vpux::VPU::arch40xx::registerVPUPipelines() {
    mlir::PassPipelineRegistration<VPU::arch40xx::DefaultHWOptions>(
            "default-hw-mode-vpu", "VPU dialect part of Default HW pipeline",
            [](mlir::OpPassManager& pm, const VPU::arch40xx::DefaultHWOptions& options) {
                VPU::arch40xx::buildDefaultHWPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<vpux::arch40xx::MCAndTilingOptionsDevice>(
            "incremental-pipeline", "Apply Incremental Pipeline",
            [](mlir::OpPassManager& pm, const vpux::arch40xx::MCAndTilingOptionsDevice& options) {
                VPU::arch40xx::buildIncrementalPipeline(pm, vpux::MCAndTilingOptionsBase(options));
            });

    mlir::PassPipelineRegistration<vpux::arch40xx::MCAndTilingOptionsDevice>(
            "sm-pipeline", "Apply SM Pipeline",
            [](mlir::OpPassManager& pm, const vpux::arch40xx::MCAndTilingOptionsDevice& options) {
                VPU::buildSMPipeline(pm, vpux::MCAndTilingOptionsBase(options));
            });
}
