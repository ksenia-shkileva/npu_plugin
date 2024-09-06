//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU37XX/pipelines.hpp"
#include "vpux/compiler/NPU37XX/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/core/passes.hpp"
#include "vpux/compiler/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include <mlir/Pass/PassManager.h>
#include <mlir/Transforms/Passes.h>

using namespace vpux;

void vpux::IE::arch37xx::buildOptimizeActivationsPipeline(mlir::OpPassManager& pm,
                                                          const OptimizeActivationsOptions& options, Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();

    pm.addPass(IE::createSwapOperationsPass(isOptionEnabled(options.enableSEPtrsOperations) ||
                                                    isOptionEnabled(options.enableExperimentalSEPtrsOperations),
                                            log));
    pm.addPass(IE::arch37xx::createInsertIdentityPoolBeforeOpPass(log));
    pm.addPass(IE::arch37xx::createSwapMaxPoolWithActivation(log));
    pm.addPass(IE::createFuseActivationOpsPass(options.enableFuseClampOperations, log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
}

void vpux::IE::arch37xx::buildMemPermutePositioningPipeline(mlir::OpPassManager& pm,
                                                            const MemPermutePositioningOptions& options, Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();
    pm.addPass(IE::createConvertToMemPermutePass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createPropagateMemPermuteThroughSoftMaxPass(log));
    pm.addPass(IE::createMovePermutePostEltwisePass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createLegalizeNDMemPermutePass(log));
    pm.addPass(IE::createPropagateMemPermuteBeforeOpPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createPropagateMemPermuteThroughAddPass(log));
    pm.addPass(IE::createUniquifyOpsPass(log));
    pm.addPass(IE::createAdjustMemPermuteAroundOpPass(log));
    pm.addPass(IE::createExpandMatMulSoftMaxMatMulPass(options.enableGroupedMatMul, log));
}

void vpux::IE::arch37xx::buildMemPermuteProcessingPipeline(mlir::OpPassManager& pm, Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();
    pm.addPass(IE::createSwapMemPermuteAndExpandPass(log));
    pm.addPass(IE::createPropagateMemPermuteBeforeOpPass(log));
    pm.addPass(IE::arch37xx::createInsertIdentityPoolBeforeOpPass(log));
    pm.addPass(IE::createFuseMemPermutePass(log));
    pm.addPass(IE::createConvertMemPermuteToPoolPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createUniquifyOpsPass(log));
}

void vpux::IE::arch37xx::buildExpandAndOptimizeActivationChannelsPipeline(
        mlir::OpPassManager& pm, const ExpandActivationChannelsOptions& options, Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();
    if (options.enableExpandActivationChannels) {
        if (options.enableAdjustConvShapePass) {
            pm.addPass(IE::createOptimizeAvgPoolWithUnalignedChannelsPass(log));
            pm.addPass(IE::createAdjustConvolutionShapePass(log));
        }
        pm.addPass(IE::arch37xx::createExpandActivationChannelsPass(
                /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
                /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
        pm.addPass(mlir::createCanonicalizerPass(grc));

        if (options.enableOptimizeSliceExpand) {
            pm.addPass(IE::arch37xx::createOptimizeSliceExpandPass(log));
        }

        pm.addPass(IE::createAdjustConvolutionWeightsPass(log));
        pm.addPass(IE::createAdjustConvolutionInputShapePass(log));
        pm.addPass(IE::createAdjustInputShapePass(log));
        pm.addPass(mlir::createCanonicalizerPass(grc));
        if (options.enableOptimizeSliceExpand) {
            pm.addPass(IE::arch37xx::createOptimizeSliceExpandPass(log));
        }
        pm.addPass(IE::createUniquifyOpsPass(log));
        pm.addPass(IE::createPropagateAffineReshapePass(log));
        pm.addPass(IE::createUniquifyBranchesPass(log));

        if (options.enableFusePermuteQuantizeExpand) {
            pm.addPass(IE::arch37xx::createPropagateExpandPass(log));
            pm.addPass(IE::arch37xx::createFusePermuteQuantizeExpandPass(log));
            // Convert reorder to permuteQuantize after OptimizeReordersPass if it's feasible
            // Such as Reorder(ui8)-Convert(ui->f16)-Expand to Convert(ui8->f16)-Expand-Reorder(f16)
            pm.addPass(IE::createConvertReorderToPermuteQuantizePass(log));
        }
    }

    pm.addPass(IE::createSwapOperationsPass(isOptionEnabled(options.enableSEPtrsOperations) ||
                                                    isOptionEnabled(options.enableExperimentalSEPtrsOperations),
                                            log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createConvertSplitConcatToTransposePass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
}

void vpux::IE::arch37xx::buildOptimizeMemPermuteAndActivationChannelsExpandPipeline(
        mlir::OpPassManager& pm, const ExpandActivationChannelsOptions& options, Logger log) {
    IE::arch37xx::buildMemPermutePositioningPipeline(pm, IE::MemPermutePositioningOptions(options), log);
    IE::arch37xx::buildExpandAndOptimizeActivationChannelsPipeline(pm, options, log);
    IE::arch37xx::buildMemPermuteProcessingPipeline(pm, log);
}

//
// InitialLowPrecisionTransformations
//

void vpux::IE::arch37xx::buildInitialLowPrecisionTransformationsPipeline(
        mlir::OpPassManager& pm, const IE::LowPrecisionTransformOptions& options, Logger log) {
    pm.addPass(IE::createConvertScalarToTensorPass(log));
    pm.addPass(IE::createConvertMinMaxToClampPass(log));
    pm.addPass(IE::createWeightsDequantizeToFakeQuantizePass(options, log));
}

//
// InitialTransformations
//

void vpux::IE::arch37xx::buildInitialTransformationsPipeline(mlir::OpPassManager& pm,
                                                             const arch37xx::TransformOptions& options, Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();

    pm.addPass(IE::createFuseFQAndMulPass(log));
    pm.addPass(IE::createEltwiseFakeQuantizeFusionPass(log));

    pm.addPass(createStopLocationVerifierPass(log));

    pm.addPass(IE::createUnrollTensorIteratorPass(log));
    pm.addPass(IE::createNormalizeL2FusionPass(log));
    pm.addPass(IE::createMVNFusionPass(log));
    if (options.enableConvertFFTToConv) {
        pm.addPass(IE::arch37xx::createConvertFFTToConvPass(log));
    }
    pm.addPass(IE::createDecomposeLSTMCellPass(log));
    pm.addPass(IE::createSwapMultiplyWithMatmulPass(log));
    pm.addPass(IE::createMatMulInputsTo2dPass(options.enableGroupedMatMul, log));
    pm.addPass(IE::createPropagateOpThroughBatchConcatPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createConvertMVN6ToMVN1Pass(log));
    pm.addPass(IE::createUnrollFakeQuantizePass(log));
    pm.addPass(IE::createUnrollFullyConnectedPass(log));
    pm.addPass(IE::createFuseScalesToAccumulatePass(log));
    pm.addPass(IE::createConvertMatMulToConvPass(log));
    pm.addPass(IE::arch37xx::createConvertSubGRUSequenceToConvPass(log));
    pm.addPass(IE::createConvertConvBackpropDataToTransposedConvPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createDilatedConvConvertPass(log));

    if (options.enableConvertFCToConv) {
        pm.addPass(IE::createConvertFCToConvPass(log));
    }
}

//
// LowPrecision
//

void vpux::IE::arch37xx::buildLowPrecisionPipeline(mlir::OpPassManager& pm, const LowPrecisionOptions& options,
                                                   Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();

    pm.addPass(IE::createHandleU16FakeQuantizePass(log));
    pm.addPass(IE::createFoldReLUBeforeFQPass(log));
    pm.addPass(IE::createOptimizeUnalignedQDQSeqPass(log));
    pm.addPass(IE::createSwapFakeQuantWithReshapeAndStridedSlicePass(log));
    pm.addPass(IE::createSwapConvertWithTransposeReshapePass(log));
    pm.addPass(IE::createHandleFakeQuantHasNegativeScalesPass(log));
    if (options.enableAlignScales) {
        pm.addPass(IE::createAlignScalesPass(isOptionEnabled(options.enableSEPtrsOperations), log));
    }
    if (options.enableAdjustNonZeroFakeQuant) {
        pm.addPass(IE::createAdjustNonZeroFakeQuantPass(log));
    }
    if (options.enableConvolutionMixedPrecisionDecomposition) {
        pm.addPass(IE::arch37xx::createProcessAsymmetricZeroPointsForConvolutionPass(log));
    }

    pm.addPass(IE::createSplitFakeQuantPass(log));
    pm.addPass(IE::createFuseConvertWithQuantizePass(log));
    pm.addPass(IE::createConvertToDequantizePass(options, log));
    if (options.enablePropagateQuantDequant) {
        pm.addPass(mlir::createCanonicalizerPass(grc));
        pm.addPass(IE::createPropagateQuantizeDequantizePass(isOptionEnabled(options.enableSEPtrsOperations), log));
    }
    if (options.enableSwapTransposeWithFQ) {
        pm.addPass(IE::createSwapTransposeWithFQPass(log));
    }
    pm.addPass(IE::createPropagateFqThroughConcatPass(log));
    pm.addPass(IE::createFuseQuantizedOpsPass(
            /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
            /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
    if (options.enableFP16ToU8MixedMode) {
        pm.addPass(IE::arch37xx::createOptimizeNetworkInputConvertPass(log));
    }

    pm.addPass(IE::arch37xx::createConvertWeightsToI8Pass(log));
    pm.addPass(IE::arch37xx::createConvertToMixedPrecision(isOptionEnabled(options.enableFloatInQuantWeightsMixedMode),
                                                           log));
    if (options.enableQuantDequantRemoval) {
        pm.addPass(IE::createRemoveQuantDequantSeqPass(log));
    }
    pm.addPass(IE::createConvertWeightsToU8Pass(log));
    pm.addPass(IE::createConvertWeightsToI4Pass(log));
    // After the execution of ConvertWeightsToU8 could appear new cases when FuseQuantizedOps and
    // ConvertToMixedPrecision can be applied. The execution ConvertWeightsToU8 can align the data type of the operands
    // of NCE operations to U8, condition that is necessary in rewriters like: FuseWithEltwiseConverter,
    // FloatOutAddRewriter where it required that the operands to have the same data type and this happens only after
    // execution of ConvertWeightsToU8.
    pm.addPass(IE::createFuseQuantizedOpsPass(
            /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
            /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
    pm.addPass(IE::arch37xx::createConvertToMixedPrecision(isOptionEnabled(options.enableFloatInQuantWeightsMixedMode),
                                                           log));
    if (options.enableFuseOutstandingDequant) {
        pm.addPass(IE::arch37xx::createFuseOutstandingDequant(log));
    }
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(IE::createDequantizeConstPass(log));
    pm.addPass(IE::createConvertQuantizeOpsToNceOpsPass(log));
    pm.addPass(IE::createMergeFakeQuantPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
}

//
// AdjustLayout
//

void vpux::IE::arch37xx::buildAdjustLayoutPipeline(mlir::OpPassManager& pm, const AdjustLayoutOptions& options,
                                                   Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();

    if (options.enableForceZMajorConcat) {
        pm.addPass(IE::createInsertReorderBetweenLayerAndConcatPass(log));
    }

    pm.addPass(IE::createPropagateAffineReshapePass(log));
    pm.addPass(IE::createPropagateTransposePass(log));
    pm.addPass(IE::createUniquifyBranchesPass(log));
    pm.addPass(IE::createSwapTransposeConcatPass(log));
    pm.addPass(IE::createTransposeToPermuteCastPass(log));
    pm.addPass(IE::createAdjustLayoutsPass(
            /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
            /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
    pm.addPass(mlir::createCanonicalizerPass(grc));

    if (options.enableOptimizeReorders) {
        pm.addPass(IE::createFuseReshapeMvnPass(log));
        pm.addPass(IE::createOptimizeReordersPass(
                /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
                /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
        pm.addPass(IE::createOptimizeReordersAcrossFunctionCallsPass(
                /*seOpsEnabled=*/isOptionEnabled(options.enableSEPtrsOperations),
                /*seExperimentalOpsEnabled=*/isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
        pm.addPass(IE::createUniquifyOpsPass(log));
        pm.addPass(IE::createUniquifyBranchesPass(log));
        pm.addPass(IE::arch37xx::createPropagateReorderToNCEPass(log));
        pm.addPass(IE::arch37xx::createFuseReordersPass(log));
        pm.addPass(mlir::createCanonicalizerPass(grc));
    }
}

//
// DefaultHWPipeline
//

void vpux::IE::arch37xx::buildDefaultHWPipeline(mlir::OpPassManager& pm, const IE::arch37xx::DefaultHWOptions& options,
                                                Logger log) {
    const auto grc = getDefaultGreedyRewriteConfig();

    if (options.enableFunctionOutlining) {
        pm.addPass(mlir::createCanonicalizerPass(grc));
        pm.addPass(IE::createOutlinerPass(options.functionOutliningMode, log));
    }

    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(createStartLocationVerifierPass(log, options.locationsVerificationMode));

    // Level 3 : Topology
    if (options.logOpOptimizations) {
        pm.addPass(IE::createLogOpOptimizationsPass());
    }

    pm.addPass(IE::createReshapeMatMulInputsPass(options.enableGroupedMatMul, log));
    IE::arch37xx::buildInitialLowPrecisionTransformationsPipeline(pm, IE::LowPrecisionTransformOptions(options), log);
    IE::arch37xx::buildInitialTransformationsPipeline(pm, IE::arch37xx::TransformOptions(options), log);
    IE::buildAdjustPrecisionPipeline(pm, IE::AdjustPrecisionOptions(options), log);

    IE::buildOperationConversionPipeline(pm, log);

    pm.addPass(IE::createConvertNceOpsTo4DPass(log));
    pm.addPass(IE::createUnrollConv3dToConv2dPass(log));
    if (options.enableHandleLargeKernel) {
        pm.addPass(IE::createAdjustMaxPoolInputShapePass(log));
        pm.addPass(IE::createHandleLargeKernelsPass(log));
    }
    pm.addPass(IE::createHandleExcludePadForAvgPoolPass(log));
    if (options.enableConvertAvgPoolToDWConv) {
        pm.addPass(IE::createConvertAvgPoolToDWConvPass(log));
    }

    pm.addPass(IE::createAdaptShapesForScaleShiftPass(log));
    pm.addPass(IE::createResolveStridedSlicePass(log));
    pm.addPass(IE::createSwapTransposeConcatPass(log));
    pm.addPass(IE::createConvertSplitConcatToTransposePass(log));
    pm.addPass(IE::createConvertShapeTo4DPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    pm.addPass(
            IE::createConvertToSpatialOpPass(false, isOptionEnabled(options.enableExperimentalSEPtrsOperations), log));
    pm.addPass(IE::createSwapOperationsPass(isOptionEnabled(options.enableSEPtrsOperations) ||
                                                    isOptionEnabled(options.enableExperimentalSEPtrsOperations),
                                            log));
    pm.addPass(IE::createSwapPadLayerPass(log));
    pm.addPass(IE::createConvertSubtractToAddPass(log));
    pm.addPass(IE::createConvertToScaleShiftPass(log));
    pm.addPass(IE::createBroadcastInputForAddPass(log));
    pm.addPass(IE::createConvertGRNToNormalizeL2Pass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    // E#79878: Solve eltwise single layer test failure.
    // SwapOperations pass may generate non-4D AddOp.
    // If AddOp appears here means that it cannot be fused into NCE task.
    // So convert it's shape to 4D and then convert this AddOp to ScaleShift.
    pm.addPass(IE::createConvertShapeTo4DPass(log));
    pm.addPass(IE::createConvertToScaleShiftPass(log));
    pm.addPass(IE::createResolveScatterUpdateByTransposePass(log));
    pm.addPass(IE::createConvertGroupConvToConvPass(log));
    pm.addPass(IE::createSwapOperationsPass(isOptionEnabled(options.enableSEPtrsOperations) ||
                                                    isOptionEnabled(options.enableExperimentalSEPtrsOperations),
                                            log));

    pm.addPass(IE::createConvertDepth2SpaceToTransposedConvPass(log));
    pm.addPass(IE::createSwapD2SAndScaleShiftPass(log));

    IE::buildAdjustForVPUPipeline(pm, IE::AdjustForVPUOptions(options), log);

    pm.addPass(IE::createHandleExcludePadForAvgPoolPass(log));
    pm.addPass(IE::createResolveStridedSlicePass(log));

    if (options.enableSwapTransposeWithFQ) {
        pm.addPass(IE::createSwapTransposeWithFQPass(log));
    }
    if (options.enableSplitConvWithMultipleFQ) {
        pm.addPass(IE::createSplitConvWithMultipleFQPass(log));
    }
    pm.addPass(mlir::createCanonicalizerPass(grc));

    if (options.enableHandleLargeKernel) {
        pm.addPass(IE::createHandleLargeKernelsPass(log));
    }
    if (options.enableHandleLargeStrides) {
        pm.addPass(IE::createHandleLargeStridesPass(log));
    }
    if (options.enableHandleAsymmetricStrides) {
        pm.addPass(IE::createHandleAsymmetricStridesPass(log));
    }
    if (options.enableHandleLargePads) {
        pm.addPass(IE::createHandleLargePadsPass(log));
    }
    pm.addPass(IE::createConvertGroupConvToConvPass(log));
    pm.addPass(mlir::createCanonicalizerPass(grc));
    if (options.enableOptimizeScaleShiftToDWConv) {
        IE::buildScaleShiftProcessingPipeline(pm, log);
    }

    pm.addPass(IE::createFuseActivationOpsPass(options.enableFuseClampOperations, log));
    pm.addPass(IE::createConvertStridedSlice2ConvPass(log));
    if (options.enableLowPrecision) {
        IE::arch37xx::buildLowPrecisionPipeline(pm, IE::LowPrecisionOptions(options), log);
        pm.addPass(IE::createConvertShapeTo4DPass(log));
        pm.addPass(IE::createSwapViewOpAndClampPass(log));
    }
    IE::arch37xx::buildOptimizeActivationsPipeline(pm, IE::OptimizeActivationsOptions(options), log);

    // Note: this pass depends on DequantizeConst pass (part of
    // buildLowPrecisionPipeline) to eliminate potential quantization ops on
    // constant operands
    pm.addPass(IE::createConvertDivideToMultiplyPass(log));
    // Note: apply FuseMultiplyToConv after ConvertDivideToMultiply to increase
    // the applicability
    pm.addPass(IE::arch37xx::createFuseMultiplyToConvPass(log));

    if (options.enableSEPtrsOperations && options.enableSplitBilinerIntoHAndW) {
        pm.addPass(IE::createSplitBilinerIntoHAndWPass(log));
    }

    if (options.enableBilinearInterpolateOnDPU) {
        pm.addPass(IE::arch37xx::createMapBilinearInterpolateOnDPUPass(isOptionEnabled(options.enableSEPtrsOperations),
                                                                       log));
    }

    pm.addPass(IE::createConvertBatchedLayerTo1NPass(log));
    pm.addPass(IE::arch37xx::createUnrollBatchPass(log, isOptionEnabled(options.skipUnrollBatch)));

    if (options.enableUpstreamSlice) {
        pm.addPass(IE::createUpstreamSlicePass(log));
    }
    pm.addPass(IE::createOptimizeGroupConvConcatPass(log));

    pm.addPass(IE::createFuseConvWithSlicePass(log));

    pm.addPass(IE::createSwapMVNWithTransposePass(log));

    IE::arch37xx::buildAdjustLayoutPipeline(pm, IE::AdjustLayoutOptions(options), log);
    pm.addPass(IE::createConvertAssignReadValueToReturnsAndInputs(log));

    if (options.enableFusePermuteQuantize) {
        pm.addPass(IE::createFusePermuteQuantizePass(false, log));
        pm.addPass(IE::createConvertReorderToPermuteQuantizePass(log));
    }

    if (options.enableExpandActivationChannels) {
        pm.addPass(IE::createAdjustGroupConvShapePass(log));
    }
    IE::arch37xx::buildOptimizeMemPermuteAndActivationChannelsExpandPipeline(
            pm, IE::ExpandActivationChannelsOptions(options), log);

    pm.addPass(IE::createRemoveViewLikeOpsChainPass(log));

    if (options.enableExpandActivationChannels) {
        pm.addPass(IE::createExpandActivationWidthPass(log));
        pm.addPass(IE::createAdjustInputShapePass(log));
        pm.addPass(mlir::createCanonicalizerPass(grc));
        pm.addPass(IE::createPropagateAffineReshapePass(log));
        if (options.enableOptimizeSliceExpand) {
            pm.addPass(IE::arch37xx::createOptimizeSliceExpandPass(log));
        }
        pm.addPass(mlir::createCanonicalizerPass(grc));
    }
    if (options.enableOptimizeSliceWithStride) {
        pm.addPass(IE::createOptimizeSliceWithStridePass(log));
        if (options.enableAdjustConvShapePass) {
            pm.addPass(IE::createAdjustConvolutionShapePass(log));
        }
    }
    if (options.enableConvertExpandToConvPass) {
        pm.addPass(IE::createConvertExpandToConvPass(log));
    }
    pm.addPass(IE::createPropagateShapeCastPass(log));
    pm.addPass(IE::createOptimizeIdentityPoolPass(log));
    if (options.logOpOptimizations) {
        pm.addPass(IE::createLogOpOptimizationsPass());
    }
}

//
// registerIEPipelines
//

void vpux::IE::arch37xx::registerIEPipelines() {
    mlir::PassPipelineRegistration<IE::arch37xx::DefaultHWOptions>(
            "default-hw-mode-ie", "IE dialect part of Default HW pipeline",
            [](mlir::OpPassManager& pm, const IE::arch37xx::DefaultHWOptions& options) {
                IE::arch37xx::buildDefaultHWPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<IE::LowPrecisionTransformOptions>(
            "initial-low-precision-transformations",
            "[LEGALIZATION] Initial Low Precision Transformations, convert initial low precision IR operations to "
            "equivalent operations supported by the lower compilation levels",
            [](mlir::OpPassManager& pm, const IE::LowPrecisionTransformOptions& options) {
                IE::arch37xx::buildInitialLowPrecisionTransformationsPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<arch37xx::TransformOptions>(
            "initial-transformations",
            "[LEGALIZATION] Initial Transformations, convert initial IR operations to another and tries to reduce the "
            "number of op types used in the graph",
            [](mlir::OpPassManager& pm, const arch37xx::TransformOptions& options) {
                IE::arch37xx::buildInitialTransformationsPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<OptimizeActivationsOptions>(
            "optimize-activations", "[OPTIMIZATION] Optimize activations for VPU target",
            [](mlir::OpPassManager& pm, const OptimizeActivationsOptions& options) {
                IE::arch37xx::buildOptimizeActivationsPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<MemPermutePositioningOptions>(
            "mempermute-positioning",
            "[OPTIMIZATION] MemPermute positioning is responsible for handling data transfromations ops (Transpose, "
            "Reshape etc), transform it to MemPermute and reorder the op to optimize final subgraph to avoid "
            "unnecessary data permutations",
            [](mlir::OpPassManager& pm, const MemPermutePositioningOptions& options) {
                IE::arch37xx::buildMemPermutePositioningPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<ExpandActivationChannelsOptions>(
            "expand-and-optimize-activation-channels", "[OPTIMIZATION] Expand and optimize activation channels",
            [](mlir::OpPassManager& pm, const ExpandActivationChannelsOptions& options) {
                IE::arch37xx::buildExpandAndOptimizeActivationChannelsPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<mlir::EmptyPipelineOptions>(
            "mempermute-processing",
            "[OPTIMIZATION] MemPermute processing is responsible for handling mempermute op and optimize final "
            "subgraph to avoid unnecessary data "
            "permutations",
            [](mlir::OpPassManager& pm) {
                IE::arch37xx::buildMemPermuteProcessingPipeline(pm);
            });

    mlir::PassPipelineRegistration<ExpandActivationChannelsOptions>(
            "optimize-mempermute-and-activation-channels-expand",
            "[OPTIMIZATION] Optimize MemPermute and activation channels expand",
            [](mlir::OpPassManager& pm, const ExpandActivationChannelsOptions& options) {
                IE::arch37xx::buildOptimizeMemPermuteAndActivationChannelsExpandPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<LowPrecisionOptions>(
            "low-precision", "[OPTIMIZATION] Low precision transformations",
            [](mlir::OpPassManager& pm, const LowPrecisionOptions& options) {
                IE::arch37xx::buildLowPrecisionPipeline(pm, options);
            });

    mlir::PassPipelineRegistration<AdjustLayoutOptions>(
            "adjust-layout", "[LEGALIZATION] Adjust IR layout for VPU target",
            [](mlir::OpPassManager& pm, const AdjustLayoutOptions& options) {
                IE::arch37xx::buildAdjustLayoutPipeline(pm, options);
            });
}
