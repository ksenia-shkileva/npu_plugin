//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/transforms/passes.hpp"
#include "vpux/compiler/dialect/VPU/utils/const_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/nce_sparsity.hpp"

using namespace vpux;

namespace {

//
// RecomputeSparsityPtrsPass
//

class RecomputeSparsityPtrsPass final : public VPU::RecomputeSparsityPtrsBase<RecomputeSparsityPtrsPass> {
public:
    explicit RecomputeSparsityPtrsPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

//
// safeRunOnFunc
//

void RecomputeSparsityPtrsPass::safeRunOnFunc() {
    auto func = getOperation();

    using SparsityPtrStepType = int32_t;
    using WeightsAndWeightsTable = std::pair<SparsityPtrStepType, Const::DeclareOp>;
    // Note: use { step, weightsTableop } as key since these are (so far) the
    // only changing parameters. technically, this could mean less calculations
    // vs { sparseTensorOp, weightsTableOp } keys.
    DenseMap<WeightsAndWeightsTable, mlir::Value> localWeightsTableCache;
    const auto getCachedRecomputedWeightsTable = [&](VPU::GroupSparseTensorOp weightsOp,
                                                     Const::DeclareOp weightsTableConstOp) {
        auto sparsityMap = weightsOp.getSparsityMap();
        const auto sparsityMapShape = sparsityMap.getType().cast<vpux::NDTypeInterface>().getShape();

        int32_t sparsityPtrOffset = 0;
        auto workloadSize = sparsityMapShape[Dims4D::Filter::IC] * sparsityMapShape[Dims4D::Filter::KY] *
                            sparsityMapShape[Dims4D::Filter::KX];
        const int32_t sparsityPtrStep = static_cast<int32_t>(Bit(workloadSize).to<Byte>().count());

        const auto pair = std::make_pair(sparsityPtrStep, weightsTableConstOp);
        auto it = localWeightsTableCache.find(pair);
        if (it != localWeightsTableCache.end()) {
            return it->second;
        }

        const auto weightsTableContent = weightsTableConstOp.getContent();
        const auto weightsTableContentRange = weightsTableContent.getValues<int32_t>();
        std::vector<int32_t> weightsTableValues(weightsTableContentRange.begin(), weightsTableContentRange.end());

        _log.nest().trace("Sparsity pointer step '{0}' for sparsity map of shape '{1}'", sparsityPtrStep,
                          sparsityMapShape);

        const auto newWeightsTableValues =
                VPU::NCESparsity::patchWeightsTableSparsityPtrs(weightsTableValues, sparsityPtrOffset, sparsityPtrStep);

        mlir::OpBuilder builder(weightsTableConstOp);
        auto newWeightsTable =
                VPU::createWeightsTableTensor(builder, weightsTableConstOp.getLoc(), newWeightsTableValues);

        it = localWeightsTableCache.insert({pair, newWeightsTable}).first;
        return it->second;
    };

    func->walk([&](VPU::NCEOpInterface nceOp) {
        const auto weights = nceOp.getWeightsOperand();
        if (weights == nullptr || !weights.getType().isa<VPU::SparseTensorType>()) {
            return;
        }

        const auto weightsTable = nceOp.getWeightsTableOperand();
        VPUX_THROW_UNLESS(weightsTable != nullptr, "Missing weights table for operation with sparse weights");
        auto weightsTableConstOp = weightsTable.getDefiningOp<Const::DeclareOp>();
        if (weightsTableConstOp == nullptr) {
            return;
        }

        _log.trace("Recomputing sparsity pointers for '{0}' at '{1}'", nceOp->getName(), nceOp->getLoc());

        auto weightsOp = weights.getDefiningOp<VPU::GroupSparseTensorOp>();
        auto newWeightsTable = getCachedRecomputedWeightsTable(weightsOp, weightsTableConstOp);

        weightsTableConstOp.getResult().replaceUsesWithIf(newWeightsTable,
                                                          [useToReplace = nceOp.getOperation()](mlir::OpOperand& use) {
                                                              return use.getOwner() == useToReplace;
                                                          });
        if (weightsTableConstOp->getUses().empty()) {
            weightsTableConstOp->erase();
        }
    });
}

}  // namespace

//
// createRecomputeSparsityPtrsPass
//

std::unique_ptr<mlir::Pass> vpux::VPU::createRecomputeSparsityPtrsPass(Logger log) {
    return std::make_unique<RecomputeSparsityPtrsPass>(log);
}
