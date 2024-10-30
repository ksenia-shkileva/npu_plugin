//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU37XX/dialect/VPURT/transforms/passes.hpp"
#include "vpux/compiler/core/passes.hpp"
#include "vpux/compiler/dialect/VPURT/transforms/passes.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include <mlir/Pass/PassManager.h>
#include <mlir/Transforms/Passes.h>

using namespace vpux;

//
// BarrierLegalization
//

void vpux::VPURT::buildBarrierLegalizationPipeline(mlir::OpPassManager& pm, const bool wlmFlag,
                                                   std::optional<int> virtualBarrierThresholdforWlm,
                                                   const bool unevenVariantSplitFlag, Logger log) {
    pm.addPass(VPURT::createSplitExceedingVariantCountBarriersPass(log));
    pm.addPass(VPURT::createSatisfyOneWaitBarrierPerTaskPass(wlmFlag, virtualBarrierThresholdforWlm,
                                                             unevenVariantSplitFlag, log));
    pm.addPass(VPURT::createReduceExceedingActiveCountBarriersPass(wlmFlag, virtualBarrierThresholdforWlm,
                                                                   unevenVariantSplitFlag, log));
}

//
// registerVPURTPipelines
//

void VPURT::registerVPURTPipelines() {
    mlir::PassPipelineRegistration<>("barrier-legalization", "Barrier Legalization", [](mlir::OpPassManager& pm) {
        VPURT::buildBarrierLegalizationPipeline(pm);
    });
}
