//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

//

#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include <mlir/IR/PatternMatch.h>
#include <mlir/Transforms/GreedyPatternRewriteDriver.h>

using namespace vpux;

namespace {

//
// FoldReLUBeforeFQ
//

class FoldReLUBeforeFQ final : public mlir::OpRewritePattern<IE::ReLUOp> {
public:
    FoldReLUBeforeFQ(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::ReLUOp>(ctx), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(IE::ReLUOp reluOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult FoldReLUBeforeFQ::matchAndRewrite(IE::ReLUOp reluOp, mlir::PatternRewriter& rewriter) const {
    for (auto user : reluOp.getResult().getUsers()) {
        auto fakeQuantOp = mlir::dyn_cast<IE::FakeQuantizeOp>(user);
        if (fakeQuantOp == nullptr) {
            return mlir::failure();
        }

        auto inputLowConst = fakeQuantOp.getInputLow().getDefiningOp<Const::DeclareOp>();
        if (inputLowConst == nullptr) {
            return mlir::failure();
        }

        auto inputLowContent = inputLowConst.getContent();
        auto inputLowValues = inputLowContent.getValues<float>();

        auto hasNegativeInputLowVals = std::any_of(inputLowValues.begin(), inputLowValues.end(), [](float val) {
            return val < 0;
        });
        if (hasNegativeInputLowVals) {
            return mlir::failure();
        }
    }

    _log.nest().trace("Folded ReLU at '{0}'", reluOp.getLoc());
    rewriter.replaceOp(reluOp, reluOp.getInput());

    return mlir::success();
}

//
// FoldClampBeforeFQ
//

class FoldClampBeforeFQ final : public mlir::OpRewritePattern<IE::ClampOp> {
public:
    FoldClampBeforeFQ(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::ClampOp>(ctx), _log(log) {
    }

public:
    mlir::LogicalResult matchAndRewrite(IE::ClampOp clampOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult FoldClampBeforeFQ::matchAndRewrite(IE::ClampOp clampOp, mlir::PatternRewriter& rewriter) const {
    for (auto user : clampOp.getResult().getUsers()) {
        auto fakeQuantOp = mlir::dyn_cast<IE::FakeQuantizeOp>(user);
        if (fakeQuantOp == nullptr) {
            return mlir::failure();
        }

        auto inputLowConst = fakeQuantOp.getInputLow().getDefiningOp<Const::DeclareOp>();
        if (inputLowConst == nullptr) {
            return mlir::failure();
        }
        auto inputHighConst = fakeQuantOp.getInputHigh().getDefiningOp<Const::DeclareOp>();
        if (inputHighConst == nullptr) {
            return mlir::failure();
        }

        auto inputLowContent = inputLowConst.getContent();
        auto inputLowValues = inputLowContent.getValues<float>();
        auto inputHighContent = inputHighConst.getContent();
        auto inputHighValues = inputHighContent.getValues<float>();

        const auto minVal = clampOp.getMinAttr().getValueAsDouble();
        const auto maxVal = clampOp.getMaxAttr().getValueAsDouble();

        auto inputLowVals = std::any_of(inputLowValues.begin(), inputLowValues.end(), [minVal](float val) {
            return val < minVal;
        });
        auto inputHighVals = std::any_of(inputHighValues.begin(), inputHighValues.end(), [maxVal](float val) {
            return val > maxVal;
        });
        if (inputLowVals && inputHighVals) {
            return mlir::failure();
        }
    }

    _log.nest().trace("Folded Clamp at '{0}'", clampOp.getLoc());
    rewriter.replaceOp(clampOp, clampOp.getInput());

    return mlir::success();
}

//
// FoldActivationBeforeFQPass
//

class FoldActivationBeforeFQPass final : public IE::FoldActivationBeforeFQBase<FoldActivationBeforeFQPass> {
public:
    explicit FoldActivationBeforeFQPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

void FoldActivationBeforeFQPass::safeRunOnFunc() {
    auto& ctx = getContext();
    mlir::RewritePatternSet patterns(&ctx);
    patterns.add<FoldReLUBeforeFQ>(&ctx, _log);
    patterns.add<FoldClampBeforeFQ>(&ctx, _log);

    auto func = getOperation();
    if (mlir::failed(mlir::applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }
}

}  // namespace

std::unique_ptr<mlir::Pass> vpux::IE::createFoldActivationBeforeFQPass(Logger log) {
    return std::make_unique<FoldActivationBeforeFQPass>(log);
}
