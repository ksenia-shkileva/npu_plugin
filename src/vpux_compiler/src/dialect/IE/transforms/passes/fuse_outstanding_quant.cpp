//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/transforms/factories/fuse_outstanding_quant_strategy_getter.hpp"
#include "vpux/compiler/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

namespace vpux {

//
// FuseOutstandingQuantPass
//

class FuseOutstandingQuantPass final : public IE::FuseOutstandingQuantBase<FuseOutstandingQuantPass> {
public:
    explicit FuseOutstandingQuantPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

    mlir::LogicalResult initialize(mlir::MLIRContext* ctx) final;

private:
    void safeRunOnFunc() final;
};

mlir::LogicalResult FuseOutstandingQuantPass::initialize(mlir::MLIRContext* ctx) {
    if (mlir::failed(Base::initialize(ctx))) {
        return mlir::failure();
    }

    return mlir::success();
}

void FuseOutstandingQuantPass::safeRunOnFunc() {
    auto& ctx = getContext();
    auto func = getOperation();

    mlir::RewritePatternSet patterns(&ctx);

    // register platform specific rewriters using the platform specific strategy
    auto strategy = vpux::IE::createFuseOutstandingQuantStrategy(func);
    strategy->addPatterns(patterns, _log);

    if (mlir::failed(applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }
}

}  // namespace vpux

//
// createFuseOutstandingQuantPass
//

std::unique_ptr<mlir::Pass> vpux::IE::createFuseOutstandingQuantPass(Logger log) {
    return std::make_unique<FuseOutstandingQuantPass>(log);
}
