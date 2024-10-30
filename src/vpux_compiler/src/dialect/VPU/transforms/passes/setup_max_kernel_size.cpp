//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include <cstddef>
#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/transforms/factories/max_kernel_size_constant.hpp"
#include "vpux/compiler/dialect/VPU/transforms/passes.hpp"
#include "vpux/compiler/dialect/VPU/utils/max_kernel_size_utils.hpp"
#include "vpux/compiler/utils/analysis.hpp"
#include "vpux/utils/core/error.hpp"
using namespace vpux;

namespace {

//
// SetupMaxKernelSizePass
//

class SetupMaxKernelSizePass final : public VPU::SetupMaxKernelSizeBase<SetupMaxKernelSizePass> {
public:
    SetupMaxKernelSizePass() = default;
    SetupMaxKernelSizePass(const VPU::InitCompilerOptions& initCompilerOptions, Logger log) {
        Base::initLogger(log, Base::getArgumentName());
        Base::copyOptionValuesFrom(initCompilerOptions);

        initializeFromOptions();
    }

private:
    mlir::LogicalResult initializeOptions(StringRef options) final;
    void safeRunOnModule() final;

private:
    // Initialize fields from pass options
    void initializeFromOptions();

private:
    bool _allowCustomValues = false;
};

void addConstant(mlir::OpBuilder optionsBuilder, IE::PipelineOptionsOp pipelineOptionsOp, mlir::StringRef constantName,
                 int64_t constantValue, bool allowCustomValues) {
    auto hasPipelineOption = pipelineOptionsOp.lookupSymbol<IE::OptionOp>(constantName) != nullptr;
    VPUX_THROW_WHEN(!allowCustomValues && hasPipelineOption,
                    "Kernel size constant is already defined, probably you run '--init-compiler' twice");

    if (hasPipelineOption) {
        return;
    }
    auto* ctx = optionsBuilder.getContext();
    mlir::IntegerType sizeType = mlir::IntegerType::get(ctx, sizeof(void*) * 8, mlir::IntegerType::Signed);
    const auto constantAttr = mlir::StringAttr::get(ctx, constantName);
    optionsBuilder.create<IE::OptionOp>(optionsBuilder.getUnknownLoc(), constantAttr,
                                        mlir::IntegerAttr::get(sizeType, constantValue));
}

mlir::LogicalResult SetupMaxKernelSizePass::initializeOptions(StringRef options) {
    if (mlir::failed(Base::initializeOptions(options))) {
        return mlir::failure();
    }

    initializeFromOptions();

    return mlir::success();
}

void SetupMaxKernelSizePass::initializeFromOptions() {
    if (allowCustomValues.hasValue()) {
        _allowCustomValues = allowCustomValues.getValue();
    }
}

void SetupMaxKernelSizePass::safeRunOnModule() {
    auto moduleOp = getModuleOp(getOperation());
    auto optionsBuilder = mlir::OpBuilder::atBlockBegin(moduleOp.getBody());
    auto pipelineOptionsOp = VPU::getPipelineOptionsOp(getContext(), moduleOp);
    optionsBuilder =
            mlir::OpBuilder::atBlockBegin(&pipelineOptionsOp.getOptions().front(), optionsBuilder.getListener());

    auto maxKernelSizeConstant = vpux::VPU::getMaxKernelSizeConstant(VPU::getArch(getOperation()));
    auto maxKernelSize = maxKernelSizeConstant.getMaxKernelSize();

    addConstant(optionsBuilder, pipelineOptionsOp, VPU::MAX_KERNEL_SIZE, maxKernelSize, _allowCustomValues);
}

}  // namespace

//
// createSetupMaxKernelSizePass
//

std::unique_ptr<mlir::Pass> vpux::VPU::createSetupMaxKernelSizePass() {
    return std::make_unique<SetupMaxKernelSizePass>();
}

std::unique_ptr<mlir::Pass> vpux::VPU::createSetupMaxKernelSizePass(const VPU::InitCompilerOptions& initCompilerOptions,
                                                                    Logger log) {
    return std::make_unique<SetupMaxKernelSizePass>(initCompilerOptions, log);
}
