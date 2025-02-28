//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/core/barrier_info.hpp"
#include "vpux/compiler/dialect/VPUIP/utils/utils.hpp"
#include "vpux/compiler/dialect/VPURT/interfaces/barrier_simulator.hpp"
#include "vpux/compiler/dialect/VPURT/transforms/passes.hpp"
#include "vpux/compiler/dialect/VPURT/utils/barrier_legalization_utils.hpp"

#include <llvm/ADT/SetOperations.h>

using namespace vpux;

namespace {

class SatisfyOneWaitBarrierPerTaskPass final :
        public VPURT::SatisfyOneWaitBarrierPerTaskBase<SatisfyOneWaitBarrierPerTaskPass> {
public:
    explicit SatisfyOneWaitBarrierPerTaskPass(const bool unevenVariantSplitFlag, Logger log)
            : _unevenVariantSplitFlag(unevenVariantSplitFlag) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
    const bool _mergeWaitBarriersIteratively = false;
    bool _unevenVariantSplitFlag;
};

void SatisfyOneWaitBarrierPerTaskPass::safeRunOnFunc() {
    auto func = getOperation();
    auto& barrierInfo = getAnalysis<BarrierInfo>();
    if (_unevenVariantSplitFlag) {
        barrierInfo.enableUnevenVariantSplit();
    }

    const auto maxAvailableSlots = maxVariantCount.hasValue() ? checked_cast<size_t>(maxVariantCount.getValue())
                                                              : VPUIP::getBarrierMaxVariantCount(func);
    const auto maxSlotsSum = VPUIP::getBarrierMaxVariantSum(func);
    _log.trace("There are {0} slots for each barrier",
               maxSlotsSum < maxAvailableSlots ? maxSlotsSum : maxAvailableSlots);

    const auto availableSlots = vpux::VPUIP::getAvailableSlots(maxSlotsSum, maxAvailableSlots);
    const auto mergeBarriersIteratively = mergeWaitBarriersIteratively.hasValue()
                                                  ? checked_cast<bool>(mergeWaitBarriersIteratively.getValue())
                                                  : _mergeWaitBarriersIteratively;

    // merge parallel wait barriers
    bool modifiedIR = barrierInfo.ensureTasksDrivenBySingleBarrier(availableSlots, mergeBarriersIteratively);

    if (!modifiedIR) {
        // IR was not modified
        barrierInfo.clearAttributes();
        return;
    }

    VPURT::orderExecutionTasksAndBarriers(func, barrierInfo);
    VPUX_THROW_UNLESS(barrierInfo.verifyControlGraphSplit(), "Encountered split of control graph is incorrect");
    barrierInfo.clearAttributes();
    VPURT::postProcessBarrierOps(func);
    VPUX_THROW_UNLESS(VPURT::verifyBarrierSlots(func, _log), "Barrier slot count check failed");
    auto hasOneWaitBarrierPerTask = VPURT::verifyOneWaitBarrierPerTask(func, _log);
    if (_mergeWaitBarriersIteratively) {
        VPUX_THROW_UNLESS(hasOneWaitBarrierPerTask, "Encountered task with more then one wait barrier");
    }
}

}  // namespace

//
// createSatisfyOneWaitBarrierPerTaskPass
//

std::unique_ptr<mlir::Pass> vpux::VPURT::createSatisfyOneWaitBarrierPerTaskPass(const bool unevenVariantSplitFlag,
                                                                                Logger log) {
    return std::make_unique<SatisfyOneWaitBarrierPerTaskPass>(unevenVariantSplitFlag, log);
}
