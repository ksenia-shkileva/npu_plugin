//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/transforms/factories/fuse_quantized_ops_strategy_getter.hpp"
#include "vpux/compiler/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

namespace vpux {

//
// FuseQuantizedOpsPass
//

class FuseQuantizedOpsPass final : public IE::FuseQuantizedOpsBase<FuseQuantizedOpsPass> {
public:
    explicit FuseQuantizedOpsPass(const bool seOpsEnabled, const bool seExperimentalOpsEnabled, Logger log)
            : _seOpsEnabled(seOpsEnabled), _seExperimentalOpsEnabled(seExperimentalOpsEnabled) {
        Base::initLogger(log, Base::getArgumentName());
    }

    mlir::LogicalResult initialize(mlir::MLIRContext* ctx) final;

private:
    void safeRunOnFunc() final;

private:
    bool _seOpsEnabled;
    bool _seExperimentalOpsEnabled;
};

mlir::LogicalResult FuseQuantizedOpsPass::initialize(mlir::MLIRContext* ctx) {
    if (mlir::failed(Base::initialize(ctx))) {
        return mlir::failure();
    }

    // When this parameter has a value, it probably comes from LIT test.
    // Override the default
    if (seOpsEnabled.hasValue()) {
        _seOpsEnabled = seOpsEnabled.getValue();
    }

    if (seExperimentalOpsEnabled.hasValue()) {
        _seExperimentalOpsEnabled = seExperimentalOpsEnabled.getValue();
    }

    return mlir::success();
}

void FuseQuantizedOpsPass::safeRunOnFunc() {
    auto& ctx = getContext();
    auto func = getOperation();

    mlir::RewritePatternSet patterns(&ctx);

    // register platform specific rewriters using the platform specific strategy
    auto strategy = vpux::IE::createFuseQuantizedOpsStrategy(func, _seOpsEnabled, _seExperimentalOpsEnabled);
    strategy->addPatterns(patterns, _log);

    if (mlir::failed(applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }
}

}  // namespace vpux

//
// createFuseQuantizedOpsPass
//

std::unique_ptr<mlir::Pass> vpux::IE::createFuseQuantizedOpsPass(const bool seOpsEnabled,
                                                                 const bool seExperimentalOpsEnabled, Logger log) {
    return std::make_unique<FuseQuantizedOpsPass>(seOpsEnabled, seExperimentalOpsEnabled, log);
}
