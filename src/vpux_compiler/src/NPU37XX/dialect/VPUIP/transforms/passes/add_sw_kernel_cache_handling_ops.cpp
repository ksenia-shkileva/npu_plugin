//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/NPU37XX/dialect/VPUIP/transforms/passes.hpp"
#include "vpux/compiler/core/cost_model_utils.hpp"
#include "vpux/compiler/dialect/VPUIP/transforms/passes.hpp"
#include "vpux/compiler/dialect/VPUIP/utils/sw_utils.hpp"
#include "vpux/compiler/dialect/VPURT/IR/task.hpp"
#include "vpux/compiler/utils/logging.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

using namespace vpux;

constexpr StringLiteral vpuTaskTypeAttrName{"VPU.task_type"};
constexpr StringLiteral cacheFlushFuncName{"cache_flush"};
constexpr StringLiteral cacheFlushInvalidateFuncName{"cache_flush_invalidate"};
constexpr StringLiteral cacheInvalidateFuncName{"cache_invalidate"};

namespace {

mlir::SymbolRefAttr createCacheHandlingFunction(mlir::MLIRContext* ctx, OpBuilderLogger& builderLog, Logger log,
                                                VPUIP::SwKernelOp origOp, mlir::StringRef functionName,
                                                VPU::ActShaveTaskType type) {
    auto origOpModule = origOp->getParentOfType<mlir::ModuleOp>();
    auto vpuswModule = vpux::VPUIP::getVPUSWModule(origOpModule, log);
    auto functionNameSymbol = mlir::SymbolRefAttr::get(ctx, functionName);
    auto functionSymbol = mlir::SymbolRefAttr::get(ctx, vpuswModule.getName().value(), {functionNameSymbol});

    // check if this functionSymbol was already created
    auto prebuiltFunction = vpuswModule.lookupSymbol<mlir::func::FuncOp>(functionName);
    if (prebuiltFunction == nullptr) {
        const auto funcType = mlir::FunctionType::get(ctx, {}, {});
        auto innerModuleBuilder = mlir::OpBuilder::atBlockBegin(vpuswModule.getBody(), &builderLog);
        auto newFuncOp =
                innerModuleBuilder.create<mlir::func::FuncOp>(mlir::UnknownLoc::get(ctx), functionName, funcType);

        // modify attributes
        newFuncOp.setSymVisibilityAttr(mlir::StringAttr::get(ctx, "private"));
        newFuncOp->setAttr(vpuTaskTypeAttrName, mlir::SymbolRefAttr::get(ctx, VPU::stringifyActShaveTaskType(type)));
    }

    return functionSymbol;
}

mlir::async::ExecuteOp createCacheHandlingSwKernel(mlir::OpBuilder builder, OpBuilderLogger& builderLog, Logger log,
                                                   mlir::Location loc, VPUIP::SwKernelOp origOp,
                                                   mlir::StringRef functionName, VPU::ActShaveTaskType type,
                                                   ArrayRef<mlir::Value> dependencies) {
    auto ctx = builder.getContext();
    auto functionSymbol = createCacheHandlingFunction(ctx, builderLog, log, origOp, functionName, type);

    const auto bodyBuilder = [&](mlir::OpBuilder& builder, mlir::Location loc, mlir::ValueRange) {
        const int64_t tileIndex = 0;
        SmallVector<mlir::Value> buffers = {};
        const auto buffersRange = mlir::ValueRange(buffers);
        auto cacheHandlingSwKernel = builder.create<VPUIP::SwKernelOp>(loc, buffersRange, buffersRange, nullptr,
                                                                       functionSymbol, getIntAttr(builder, tileIndex));
        const SmallVector<mlir::Attribute> args = {};
        vpux::VPUIP::initSwKernel(cacheHandlingSwKernel, buffersRange, buffersRange, args, log.nest());

        builder.create<mlir::async::YieldOp>(loc, std::nullopt);
    };

    auto execOp = builder.create<mlir::async::ExecuteOp>(loc, std::nullopt, dependencies, std::nullopt, bodyBuilder);
    VPUIP::VPUIPDialect::setExecutor(execOp,
                                     vpux::IndexedSymbolAttr::get(ctx, stringifyEnum(VPU::ExecutorKind::SHAVE_ACT)));
    return execOp;
}

bool isFuncArgInDDR(mlir::Value buff) {
    if (auto blockArg = mlir::dyn_cast<mlir::BlockArgument>(buff)) {
        auto parentOp = blockArg.getOwner()->getParentOp();
        if (mlir::isa_and_nonnull<mlir::func::FuncOp>(parentOp)) {
            auto buffType = buff.getType().cast<vpux::NDTypeInterface>();
            return buffType.getMemoryKind() == VPU::MemoryKind::DDR;
        }
    }
    return false;
}

bool hasAnyBlockArgOrConstBuffer(mlir::ValueRange buffers) {
    return llvm::any_of(buffers, [](mlir::Value buff) {
        return mlir::isa_and_nonnull<Const::DeclareOp>(buff.getDefiningOp()) || isFuncArgInDDR(buff);
    });
}

bool hasResultsInDDR(mlir::Value op) {
    if (isFuncArgInDDR(op)) {
        return true;
    }

    auto opResultTypes = op.getDefiningOp()->getResultTypes();
    return llvm::any_of(opResultTypes, [](mlir::Type resType) {
        return resType.cast<vpux::NDTypeInterface>().getMemoryKind() == VPU::MemoryKind::DDR;
    });
}

bool isCacheInvalidateNeeded(mlir::OperandRange dependencies) {
    for (auto dependency : dependencies) {
        if (auto depExecOp = dependency.getDefiningOp<mlir::async::ExecuteOp>()) {
            auto depExecutor = vpux::VPUIP::VPUIPDialect::getExecutorKind(depExecOp);
            if (depExecutor == VPU::ExecutorKind::SHAVE_ACT) {
                continue;
            }

            auto yieldOp = depExecOp.getBody()->getTerminator();
            auto yieldOpOperands = yieldOp->getOperands();
            for (auto operand : yieldOpOperands) {
                if (hasResultsInDDR(operand)) {
                    return true;
                }
            }
        }
    }

    return false;
}

bool isCacheFlushNeeded(ArrayRef<mlir::Operation*> users) {
    for (auto user : users) {
        if (auto userExecOp = mlir::dyn_cast<mlir::async::ExecuteOp>(user)) {
            auto userExecutor = vpux::VPUIP::VPUIPDialect::getExecutorKind(userExecOp);
            if (userExecutor != VPU::ExecutorKind::SHAVE_ACT) {
                return true;
            }
        }
    }

    return false;
}

bool hasCacheFlushDependency(mlir::OperandRange dependencies) {
    return llvm::any_of(dependencies, [](mlir::Value dependency) {
        auto depExecOp = dependency.getDefiningOp<mlir::async::ExecuteOp>();
        auto depExecutor = vpux::VPUIP::VPUIPDialect::getExecutorKind(depExecOp);
        if (depExecutor != VPU::ExecutorKind::SHAVE_ACT) {
            return false;
        }

        auto firstOp = &depExecOp.getBody()->front();
        if (auto firstSwKernel = mlir::dyn_cast<VPUIP::SwKernelOp>(firstOp)) {
            if (firstSwKernel.getKernelFunction().getLeafReference().str() == cacheFlushFuncName) {
                return true;
            }
        }
        return false;
    });
}

bool hasShaveBodyOperands(mlir::OperandRange bodyOperands) {
    return llvm::any_of(bodyOperands, [](mlir::Value operand) {
        auto operandExecOp = operand.getDefiningOp<mlir::async::ExecuteOp>();
        return vpux::VPUIP::VPUIPDialect::getExecutorKind(operandExecOp) == VPU::ExecutorKind::SHAVE_ACT;
    });
}

//
// AddSwKernelCacheHandlingOpsPass
//

class AddSwKernelCacheHandlingOpsPass final :
        public VPUIP::arch37xx::AddSwKernelCacheHandlingOpsBase<AddSwKernelCacheHandlingOpsPass> {
public:
    explicit AddSwKernelCacheHandlingOpsPass(Logger log) {
        Base::initLogger(log, Base::getArgumentName());
    }

private:
    void safeRunOnFunc() final;
};

void AddSwKernelCacheHandlingOpsPass::safeRunOnFunc() {
    auto func = getOperation();

    func.walk([&](VPUIP::SwKernelOp origOp) {
        mlir::OpBuilder builder(origOp);
        OpBuilderLogger builderLog(_log);

        auto loc = origOp.getLoc();

        auto inputBuffs = origOp.getInputs();
        auto outputBuffs = origOp.getOutputBuffs();

        // at least one input/output buffer must be in DDR
        auto ddrInputBuffs = VPUIP::getDDRBuffers(inputBuffs);
        auto ddrOutputBuffs = VPUIP::getDDRBuffers(outputBuffs);

        bool hasInputsInDDR = !ddrInputBuffs.empty();
        bool hasOutputsInDDR = !ddrOutputBuffs.empty();
        if (!hasInputsInDDR && !hasOutputsInDDR) {
            return;
        }

        if (isCacheHandlingOp(origOp)) {
            return;
        }

        auto origExecOp = origOp->getParentOfType<mlir::async::ExecuteOp>();
        auto origExecOpToken = origExecOp.getToken();

        auto origExecOpResultsUsers = origExecOp.getResults().getUsers();
        auto origExecOpResultsUsersVector = to_small_vector(origExecOpResultsUsers);

        const auto newLoc = appendLoc(loc, "_cache_handling_op");

        bool hasBlockArgOrConstInputBuffs = hasAnyBlockArgOrConstBuffer(inputBuffs);
        bool hasBlockArgOrConstOutputBuffs = hasAnyBlockArgOrConstBuffer(outputBuffs);

        // create CACHE_INVALIDATE OR CACHE_FLUSH_INVALIDATE op
        auto origExecOpDependencies = origExecOp.getDependencies();
        auto origExecOpDependenciesVector = to_small_vector(origExecOpDependencies);
        auto origExecOpBodyOperands = origExecOp.getBodyOperands();
        if (hasInputsInDDR) {
            if ((isCacheInvalidateNeeded(origExecOpDependencies) || hasBlockArgOrConstInputBuffs)) {
                builder.setInsertionPoint(origExecOp);

                VPU::ActShaveTaskType taskType;
                StringLiteral funcName = "";
                if (hasShaveBodyOperands(origExecOpBodyOperands) && !hasCacheFlushDependency(origExecOpDependencies)) {
                    taskType = VPU::ActShaveTaskType::CACHE_FLUSH_INVALIDATE;
                    funcName = cacheFlushInvalidateFuncName;
                } else {
                    taskType = VPU::ActShaveTaskType::CACHE_INVALIDATE;
                    funcName = cacheInvalidateFuncName;
                }

                auto invalidateExecOp = createCacheHandlingSwKernel(builder, builderLog, _log, newLoc, origOp, funcName,
                                                                    taskType, origExecOpDependenciesVector);
                auto invalidateExecOpToken = invalidateExecOp.getToken();

                origExecOp.getDependenciesMutable().clear();
                origExecOp.getDependenciesMutable().append(invalidateExecOpToken);
            }
        }

        // create CACHE_FLUSH op
        if (hasOutputsInDDR) {
            if (isCacheFlushNeeded(origExecOpResultsUsersVector) || hasBlockArgOrConstOutputBuffs) {
                builder.setInsertionPointAfter(origExecOp);

                auto flushTaskType = VPU::ActShaveTaskType::CACHE_FLUSH;
                auto flushExecOp =
                        createCacheHandlingSwKernel(builder, builderLog, _log, loc, origOp, cacheFlushFuncName,
                                                    flushTaskType, ArrayRef<mlir::Value>{origExecOpToken});
                auto flushExecOpToken = flushExecOp.getToken();

                for (auto user : origExecOpResultsUsersVector) {
                    auto userExecOp = mlir::dyn_cast<mlir::async::ExecuteOp>(user);
                    if (userExecOp == nullptr) {
                        continue;
                    }

                    auto origExecOpTokenPtr = llvm::find(userExecOp.getDependencies(), origExecOpToken);
                    if (origExecOpTokenPtr == userExecOp.getDependencies().end()) {
                        continue;
                    }
                    auto origExecOpTokenIndex = static_cast<unsigned>(
                            std::distance(userExecOp.getDependencies().begin(), origExecOpTokenPtr));
                    userExecOp.getDependenciesMutable().erase(origExecOpTokenIndex, 1);
                    userExecOp.getDependenciesMutable().append(flushExecOpToken);
                }
            }
        }
    });
}
}  // namespace

//
// createAddSwKernelCacheHandlingOpsPass
//

std::unique_ptr<mlir::Pass> vpux::VPUIP::arch37xx::createAddSwKernelCacheHandlingOpsPass(Logger log) {
    return std::make_unique<AddSwKernelCacheHandlingOpsPass>(log);
}
