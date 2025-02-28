//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU37XX/dialect/VPU/impl/make_ops_with_distributed_tensor_strategy.hpp"
#include "vpux/compiler/dialect/VPU/interfaces/common_rewriters/make_ops_with_distributed_tensor.hpp"

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/distributed_tensor_utils.hpp"

using namespace vpux;

//
// NCEPermuteRewriter
//

namespace {

class NCEPermuteRewriter final : public mlir::OpRewritePattern<VPU::NCEPermuteOp> {
public:
    NCEPermuteRewriter(mlir::MLIRContext* ctx, bool enableExplicitDistributedTensorAttr, Logger log)
            : mlir::OpRewritePattern<VPU::NCEPermuteOp>(ctx),
              _enableExplicitDistributedTensorAttr(enableExplicitDistributedTensorAttr),
              _log(log) {
        setDebugName("NCEPermuteRewriter");
    }

public:
    mlir::LogicalResult matchAndRewrite(VPU::NCEPermuteOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    vpux::VPU::CopyOp buildInputCopy(mlir::PatternRewriter& rewriter, VPU::ClusteredOpInterface clusteredOp,
                                     mlir::Value input, mlir::Type distType) const;
    bool _enableExplicitDistributedTensorAttr = false;
    Logger _log;
};

mlir::LogicalResult NCEPermuteRewriter::matchAndRewrite(VPU::NCEPermuteOp origOp,
                                                        mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Got '{1}' at '{2}'", getDebugName(), origOp->getName(), origOp->getLoc());

    if (!origOp.getMultiClusterStrategy().has_value()) {
        return matchFailed(_log, rewriter, origOp, "The operation does not have multi-cluster strategy.");
    }

    auto clusteredOp = mlir::dyn_cast<VPU::ClusteredOpInterface>(origOp.getOperation());
    VPUX_THROW_UNLESS(clusteredOp != nullptr, "Operation '{0}' cannot be converted to VPU::ClusteredOpInterface",
                      origOp);

    const auto nextConv = getNextCompressConv(origOp);
    const auto strategy = nextConv == nullptr ? VPU::MultiClusterStrategy::SplitOverHeight
                                              : VPU::MultiClusterStrategy::SplitOverHeightOverlapped;

    auto outputTensorType = origOp.getOutput().getType().cast<vpux::NDTypeInterface>();
    auto numClusters = VPU::getOptimalNumClusters(clusteredOp, outputTensorType.getShape(), strategy);
    const auto activationTensorDistributionMode = getActivationTensorDistributionMode(clusteredOp, strategy);
    const auto activationTensorNumTiles = getActivationTensorNumTiles(clusteredOp, numClusters.getInt(), strategy);

    const auto activationAlignment = getActivationTensorAlignment(clusteredOp, numClusters.getInt(), strategy);

    const auto neutralPads = VPU::Padding(0, 0, 0, 0);
    auto nceOp = mlir::dyn_cast<VPU::NCEOpInterface>(origOp.getOperation());
    const auto overlapParams =
            VPU::OverlapDistributionParams(nceOp.getKernelSizeVal(), neutralPads, nceOp.getStridesVal());

    auto inputTensorType = origOp.getInput().getType().cast<vpux::NDTypeInterface>();

    const auto uniformDistributedSegments = VPU::getUniformDistributedSegments(
            clusteredOp, inputTensorType.getShape().raw(), activationTensorDistributionMode, activationTensorNumTiles,
            activationAlignment.value_or(SmallVector<int64_t>{}));

    const auto inputDistType = VPU::createDistributedTensorType(
            clusteredOp, inputTensorType, activationTensorDistributionMode, activationTensorNumTiles, numClusters,
            activationAlignment.has_value() ? activationAlignment.value() : ArrayRef<int64_t>{},
            uniformDistributedSegments, _enableExplicitDistributedTensorAttr, overlapParams);
    const auto fusedDistType =
            fuseOverlapParams(clusteredOp, inputDistType, nextConv, _enableExplicitDistributedTensorAttr);

    const auto inputCopyOp = buildInputCopy(rewriter, clusteredOp, origOp.getInput(), fusedDistType);

    const auto distributedOutputTensorType =
            getDistributedOutputTypeFromOp(origOp, origOp->getResult(0).getType(), numClusters, strategy);

    SmallVector<mlir::Value> distributedCopyOps{inputCopyOp->getResult(0)};
    mlir::IRMapping mapper;
    mapper.map(origOp->getOperands(), mlir::ValueRange{distributedCopyOps});
    auto* newOp = rewriter.clone(*origOp, mapper);
    newOp->getResult(0).setType(distributedOutputTensorType);
    if (newOp->hasAttr(vpux::VPU::multiClusterStrategy)) {
        newOp->removeAttr(vpux::VPU::multiClusterStrategy);
    }
    auto outputCopyOp =
            rewriter.create<VPU::CopyOp>(newOp->getLoc(), origOp->getResult(0).getType(), newOp->getResult(0), nullptr);

    rewriter.replaceOp(origOp, outputCopyOp);

    return mlir::success();
}

vpux::VPU::CopyOp NCEPermuteRewriter::buildInputCopy(mlir::PatternRewriter& rewriter,
                                                     VPU::ClusteredOpInterface clusteredOp, mlir::Value input,
                                                     mlir::Type distType) const {
    rewriter.setInsertionPoint(clusteredOp);
    const auto memSpace = IndexedSymbolAttr::get(rewriter.getContext(), stringifyEnum(VPU::MemoryKind::CMX_NN));
    auto distributedInputCopyOp = rewriter.create<VPU::CopyOp>(clusteredOp.getLoc(), distType, input, memSpace);

    return distributedInputCopyOp;
}

}  // namespace

//
// MakeOpsWithDistributedTensorStrategy
//

void VPU::arch37xx::MakeOpsWithDistributedTensorStrategy::addPatterns(mlir::RewritePatternSet& patterns,
                                                                      Logger& log) const {
    auto ctx = patterns.getContext();
    patterns.add<VPU::NCEConvolutionRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<VPU::NCEDepthConvolutionRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr,
                                                   log);
    patterns.add<VPU::NCEMaxPoolRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<VPU::NCEAveragePoolRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<VPU::NCEEltwiseRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<VPU::NCESWRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<VPU::NCECompressConvolutionRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr,
                                                      log);
    patterns.add<VPU::NCEInterpolateRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<VPU::NCEMatMulRewriter>(ctx, _overlapParamsLookup, _enableExplicitDistributedTensorAttr, log);
    patterns.add<NCEPermuteRewriter>(ctx, _enableExplicitDistributedTensorAttr, log);
}
