//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/core/aliases_info.hpp"
#include "vpux/compiler/dialect/VPU/IR/attributes.hpp"
#include "vpux/compiler/dialect/VPU/utils/nce_sparsity.hpp"
#include "vpux/compiler/dialect/VPUIP/IR/ops.hpp"
#include "vpux/compiler/dialect/VPUIP/transforms/passes.hpp"
#include "vpux/compiler/dialect/VPUIP/utils/utils.hpp"
#include "vpux/compiler/dialect/VPURT/IR/ops.hpp"
#include "vpux/compiler/utils/constant_fusion.hpp"
#include "vpux/compiler/utils/types.hpp"

using namespace vpux;

namespace {

//
// PatchWeightsTablePass
//

class PatchWeightsTablePass final : public VPUIP::PatchWeightsTableBase<PatchWeightsTablePass> {
public:
    explicit PatchWeightsTablePass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;

    uint32_t getRootBufferPointer(mlir::Value value, uint32_t defaultValue);

    SmallVector<uint32_t> getWeightsPerClusterPointers(VPUIP::NCEClusterTaskOp nceOp, int64_t numCluster);

    // gets pointers to weights, sparsity and offset of base buffer(for fused constants)
    std::tuple<SmallVector<uint32_t>, uint32_t, uint32_t> getWeightsAndSparsityPointers(
            vpux::VPUIP::NCEClusterTaskOp nceOp, vpux::VPURT::DeclareBufferOp wtBuffer, int64_t numClusters);

    unsigned getWeightTableSize(vpux::VPUIP::NCEClusterTaskOp nceOp, SmallVector<uint32_t>& weightsPtrPerCluster,
                                uint32_t sparsityPtr, uint32_t baseOffset);

    SmallVector<int64_t> getOffsets(vpux::VPUIP::NCEClusterTaskOp nceOp, vpux::VPURT::DeclareBufferOp wtDecBuf);

    // gets DeclareOp producing weightsTable, DeclareBufferOp to which weightsTable will be loaded and
    // Operation which loads it to the buffer
    std::tuple<vpux::Const::DeclareOp, vpux::VPURT::DeclareBufferOp, mlir::Operation*> getWeightsTableLoadingChainOps(
            vpux::VPUIP::NCEClusterTaskOp nceOp);

    mlir::Operation* getLoadOpForDstBuffer(mlir::Value dstBuffer);
};

//
// safeRunOnFunc
//

void PatchWeightsTablePass::safeRunOnFunc() {
    auto funcOp = getOperation();
    // For each nceOp.weight_table find related DeclareBufferOp. Next find dmaOp which
    // fills the buffer. DmaOp's input is expected to be Const::DeclareOp which
    // should be modified by adding relocateWeightTable transformation.
    funcOp.walk([this](vpux::VPUIP::NCEClusterTaskOp nceOp) {
        auto wTable = nceOp.getWeightTable();
        if (wTable == nullptr) {
            return;
        }
        _log.trace("WeightTable identified for operation '{0}'", nceOp->getLoc());

        auto distributedType = wTable.getType().dyn_cast<VPUIP::DistributedBufferType>();
        if (distributedType != nullptr) {
            if (nceOp->hasAttr(vpux::ConstantFusing::constantsFused) &&
                (distributedType.getDistribution().getMode().getValue() == VPU::DistributionMode::SEGMENTED)) {
                VPUX_THROW("Unable to patch fused constant with segmented weightTable");
            }
        }

        auto [cstOp, wtDecBuffer, cstLoadOp] = getWeightsTableLoadingChainOps(nceOp);
        VPUX_THROW_UNLESS(cstOp != nullptr, "Couldn't find Weight Table Declare Op");
        VPUX_THROW_UNLESS(cstLoadOp != nullptr, "Couldn't find Dma Op for Weight Table");
        _log.nest().trace("Operation loading weight table '{0}' '{1}'", cstLoadOp->getName(), cstLoadOp->getLoc());
        // On top of existing transformation a new transformation is added to the content attribute
        // of weight table const. The new transformation will patch offsets in this constant
        // with sparsity and weights pointers. The pointers are passed as  parameters of the
        // new transformation.
        _log.nest().trace("Constant for patching '{0}'", cstOp->getLoc());
        auto offsets = getOffsets(nceOp, wtDecBuffer);
        auto [weightsPtrPerCluster, sparsityPtr, baseOffset] =
                getWeightsAndSparsityPointers(nceOp, wtDecBuffer, offsets.size());
        int64_t weightsElemBitSize = CHAR_BIT;
        VPUIP::SparsityCompressionAttr weightsCompression = nullptr;
        if (auto weights = nceOp.getWeights()) {
            weightsElemBitSize = getElemTypeSize(weights.getType()).count();
            weightsCompression = VPUIP::getSparsityCompressionAttr(weights.getType());
        }

        auto weightTableSize = getWeightTableSize(nceOp, weightsPtrPerCluster, sparsityPtr, baseOffset);
        const auto channelOffset = 0;

        auto newConstAttr = cstOp.getContentAttr().relocateWeightsTablePointers(
                weightsPtrPerCluster, sparsityPtr, ShapeRef(offsets), weightTableSize, weightsElemBitSize,
                weightsCompression, channelOffset);
        mlir::OpBuilder builder(cstOp);
        auto newConstOp = builder.create<Const::DeclareOp>(cstOp.getLoc(), cstOp.getOutput().getType(), newConstAttr);
        cstLoadOp->setOperand(0, newConstOp.getOutput());
        if (cstOp->getUses().empty()) {
            cstOp.erase();
        }
    });
}

std::tuple<SmallVector<uint32_t>, uint32_t, uint32_t> PatchWeightsTablePass::getWeightsAndSparsityPointers(
        vpux::VPUIP::NCEClusterTaskOp nceOp, vpux::VPURT::DeclareBufferOp wtBuffer, int64_t numClusters) {
    auto sparsityMap = nceOp.getWeightsSparsityMap();
    if (sparsityMap == nullptr) {
        sparsityMap = nceOp.getActivationWindow();
    }
    auto sparsityPtr = getRootBufferPointer(sparsityMap, VPU::NCESparsity::SPARSITY_PTR_WHEN_NO_SPARSITY);
    uint32_t baseOffset = 0;
    if (nceOp->hasAttr(vpux::ConstantFusing::constantsFused)) {
        baseOffset = wtBuffer.getByteOffset();
    }

    auto weightsPerClusterPtrs = getWeightsPerClusterPointers(nceOp, numClusters);
    return {weightsPerClusterPtrs, sparsityPtr, baseOffset};
}

unsigned PatchWeightsTablePass::getWeightTableSize(vpux::VPUIP::NCEClusterTaskOp nceOp,
                                                   SmallVector<uint32_t>& weightsPtrPerCluster, uint32_t sparsityPtr,
                                                   uint32_t baseOffset) {
    if (nceOp->hasAttr(vpux::ConstantFusing::constantsFused)) {
        auto weightsPtr = weightsPtrPerCluster[0];
        // TODO: Multi-Cluster support E#113797
        //
        // Since the order of fusion is constant it can be thought as a contiguous array with
        // offsets for various constants which can be used to figure out the num of WT entries
        //
        //       <-------WT Entries---->
        //      [_______________________|____________________________|__________]
        //     Base                    Base                         Base
        //      Fused Const/WT          Weights                      Activation Win
        //
        // We only need to patch these entries, rest all are weights/activation or both
        // When both weights and activation are present i.e. the op is CMCONV
        // Number of WT entries would be base address of weights minus base address of fused const
        if (weightsPtr > 0) {
            return (weightsPtr - baseOffset);
        }
        // When only activation is present i.e. Op is MaxPool
        // Number of WT entries is base address of activation window minus base address of fused const
        else if (sparsityPtr > 0) {
            return (sparsityPtr - baseOffset);
        }
    }
    // unfused constant or fused constant with only weight table
    auto weightTableType = nceOp.getWeightTable().getType().cast<vpux::NDTypeInterface>();
    auto shapeTotalSize = weightTableType.getShape().totalSize();
    auto elementSize = weightTableType.getElemTypeSize().count() / CHAR_BIT;
    return shapeTotalSize * elementSize;
}

SmallVector<int64_t> PatchWeightsTablePass::getOffsets(vpux::VPUIP::NCEClusterTaskOp nceOp,
                                                       vpux::VPURT::DeclareBufferOp wtDecBuf) {
    if (nceOp->hasAttr(vpux::ConstantFusing::constantsFused)) {
        // TODO: Set the correct offsets for Multi-Cluster E#113797
        return SmallVector<int64_t>{0};
    }

    SmallVector<int64_t> offsets;
    if (auto distributedType = wtDecBuf.getType().dyn_cast<VPUIP::DistributedBufferType>()) {
        auto distributionAttr = distributedType.getDistribution();
        const auto numClusters = distributionAttr.getNumClusters().getInt();
        const auto perClusterShapeOffsets = distributedType.getPerClusterMemoryShapeOffsets();
        VPUX_THROW_UNLESS(perClusterShapeOffsets.size() == checked_cast<size_t>(numClusters),
                          "Number of shape offsets '{0}' and clusters '{1}' are mismatch",
                          perClusterShapeOffsets.size(), numClusters);

        for (auto clusterOffsets : perClusterShapeOffsets | indexed) {
            if (clusterOffsets.value().size() == 4) {
                offsets.push_back(clusterOffsets.value()[Dims4D::Filter::OC]);
            } else if (clusterOffsets.value().size() == DimsGroups5D::Filter::numDims) {
                const auto groupOffset = clusterOffsets.value()[DimsGroups5D::Filter::G];
                const auto clusterShape = distributedType.getPerClusterMemoryShapes()[clusterOffsets.index()];
                offsets.push_back(groupOffset * clusterShape[DimsGroups5D::Filter::OC]);
            }
        }
    } else {
        offsets.push_back(0);
    }
    return offsets;
}

std::tuple<vpux::Const::DeclareOp, vpux::VPURT::DeclareBufferOp, mlir::Operation*>
PatchWeightsTablePass::getWeightsTableLoadingChainOps(vpux::VPUIP::NCEClusterTaskOp nceOp) {
    auto wTable = nceOp.getWeightTable();
    vpux::ValueSourceInfo aliasInfo(wTable);
    auto rootBuffers = aliasInfo.getRoots(wTable);
    const auto rootBuffer = *rootBuffers.begin();
    auto wtDecBuf = rootBuffer.getDefiningOp<VPURT::DeclareBufferOp>();
    VPUX_THROW_UNLESS(wtDecBuf != nullptr, "DeclareBufferOp expected as a weight_table parent");

    if (nceOp->hasAttr(vpux::ConstantFusing::constantsFused)) {
        mlir::Operation* op = nullptr;
        auto weightsTable = vpux::ConstantFusing::getConstAndDma(wTable, &op);
        return {weightsTable, wtDecBuf, op};
    }

    mlir::Value inputBuffer;
    // Get operation that loads weights table to CMX for NCE Task
    auto* cstLoadOp = getLoadOpForDstBuffer(wtDecBuf.getResult());
    VPUX_THROW_UNLESS(cstLoadOp != nullptr, "Operation loading weight table expected, but not located");

    // Get the constant definition op whose content will be patched
    inputBuffer = cstLoadOp->getOperand(0);
    auto cstOp = inputBuffer.getDefiningOp<Const::DeclareOp>();
    // In case weights table was spilled there can be a sequence of DMAs
    // Need to resolve it and update this DMA to have const as input directly
    while (cstOp == nullptr) {
        cstLoadOp = getLoadOpForDstBuffer(inputBuffer);
        VPUX_THROW_UNLESS(cstLoadOp != nullptr, "Next DMA op as source operation expected");

        inputBuffer = cstLoadOp->getOperand(0);
        cstOp = inputBuffer.getDefiningOp<Const::DeclareOp>();
    }
    return {cstOp, wtDecBuf, cstLoadOp};
}

// Find a DMA operation that loads data into a given buffer
mlir::Operation* PatchWeightsTablePass::getLoadOpForDstBuffer(mlir::Value dstBuffer) {
    for (const auto& user : dstBuffer.getUsers()) {
        auto dmaOp = mlir::dyn_cast<VPUIP::NNDMAOp>(user);
        if ((dmaOp != nullptr) && (dmaOp.getOutputBuff() == dstBuffer)) {
            return dmaOp.getOperation();
        }
    }
    return nullptr;
}

uint32_t PatchWeightsTablePass::getRootBufferPointer(mlir::Value value, uint32_t defaultValue) {
    if (value == nullptr) {
        return defaultValue;
    }

    vpux::ValueSourceInfo aliasInfo(value);
    auto rootBuffers = aliasInfo.getRoots(value);
    const auto rootBuffer = *rootBuffers.begin();
    auto valueDeclareBuffer = mlir::dyn_cast<VPURT::DeclareBufferOp>(rootBuffer.getDefiningOp());
    if (valueDeclareBuffer == nullptr) {
        return defaultValue;
    }
    auto basePointer = valueDeclareBuffer.getByteOffset();

    // Below code assumes that following chain exists between
    // DeclareBufferOp and value consumed by nceOp
    // DeclareBufferOp
    // ViewOps
    // NceOp
    // Only SubViewOp is assumed to contribute to offset change
    uint32_t viewOffset = 0;
    while (auto op = value.getDefiningOp()) {
        if (mlir::isa<mlir::ViewLikeOpInterface>(op)) {
            if (mlir::isa<VPUIP::SubViewOp>(op)) {
                auto offset = mlir::cast<VPUIP::SubViewOp>(op).getByteOffset();
                viewOffset += offset.count();
            }

            auto viewOp = mlir::cast<mlir::ViewLikeOpInterface>(op);
            value = viewOp.getViewSource();
        } else if (mlir::isa<VPURT::DeclareBufferOp>(op)) {
            break;
        } else {
            VPUX_THROW("Illegal op found during patching at {0}", op->getLoc());
        }
    }

    return basePointer + viewOffset;
}

SmallVector<uint32_t> PatchWeightsTablePass::getWeightsPerClusterPointers(VPUIP::NCEClusterTaskOp nceOp,
                                                                          int64_t numCluster) {
    auto weights = nceOp.getWeights();
    uint64_t weightsBasePointer = getRootBufferPointer(weights, 0);

    if (weights == nullptr || !weights.getType().isa<VPUIP::DistributedBufferType>()) {
        return SmallVector<uint32_t>(numCluster, static_cast<int32_t>(weightsBasePointer));
    }
    auto distributedType = weights.getType().dyn_cast<VPUIP::DistributedBufferType>();
    auto distributionAttr = distributedType.getDistribution();
    auto mode = distributionAttr.getMode().getValue();
    if (mode != (VPU::DistributionMode::DUPLICATED | VPU::DistributionMode::SEGMENTED)) {
        // For distribution modes except Duplicated|Segmented, the weights on every cluster is supposed to be symmetric.
        // So just return the base pointer for each weights
        return SmallVector<uint32_t>(numCluster, static_cast<int32_t>(weightsBasePointer));
    }

    // For Duplicated|Segmented weights, weights should be non const for ops like MatMul. It's supposed to
    // be segmented on N, while the entire data is copied to all CMXs. So the weight's offset need to updated
    // accordingly since it's not symmetric.
    SmallVector<uint32_t> weightsPerClusterPtrs;
    VPUX_THROW_UNLESS(nceOp.getWeightsSparsityMap() == nullptr,
                      "Weight sparisity map is found, weights is supposed to be non const at '{0}'", nceOp->getLoc());
    const auto tilingScheme = parseIntArrayAttr<int64_t>(distributionAttr.getNumTiles());
    const auto axis = vpux::VPU::getDistributedTilingAxis(tilingScheme);
    VPUX_THROW_UNLESS(axis == Dims4D::Act::N.ind(), "Invalid Tile dim, get {0}, expect tiling on N.", axis);
    const auto perClusterShapeOffsets = distributedType.getPerClusterComputeShapeOffsets();
    for (auto clusterOffsets : perClusterShapeOffsets) {
        auto perClusterOffset = Byte(clusterOffsets[Dim(axis)] * distributedType.getStrides()[Dim(axis)]).count();
        weightsPerClusterPtrs.push_back(static_cast<int32_t>(weightsBasePointer + perClusterOffset));
    }
    return weightsPerClusterPtrs;
}
}  // namespace

//
// createPatchWeightsTablePass
//

std::unique_ptr<mlir::Pass> vpux::VPUIP::createPatchWeightsTablePass(Logger log) {
    return std::make_unique<PatchWeightsTablePass>(log);
}
