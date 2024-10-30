//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/const_utils.hpp"

using namespace vpux;

mlir::LogicalResult vpux::VPU::DynamicReshapeOp::inferReturnTypes(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties props, mlir::RegionRange,
        mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::DynamicReshapeOpAdaptor reshape(operands, attrs, props);
    if (mlir::failed(reshape.verify(loc))) {
        return mlir::failure();
    }

    const auto outShape = parseIntArrayAttr<int64_t>(reshape.getOutputShapeAttr());
    const auto outBounds = parseIntArrayAttr<int64_t>(reshape.getOutputBoundsAttr());
    const auto inType = reshape.getInput().getType().cast<vpux::NDTypeInterface>();

    const auto typeComponents = TypeComponents()
                                        .setShape(Shape(outShape))
                                        .setDimsOrder(DimsOrder::fromNumDims(outShape.size()))
                                        .setBounds(getIntArrayAttr(ctx, outBounds));
    auto outType = inType.changeTypeComponents(typeComponents);

    inferredReturnTypes.push_back(outType);

    return mlir::success();
}

bool vpux::VPU::DynamicReshapeOp::fitIntoCMX(llvm::ArrayRef<vpux::NDTypeInterface> buffers, Byte reservedMem) {
    VPUX_THROW_UNLESS(buffers.size() == 3,
                      "DynamicReshapeOp requires 2 inputs and 1 output, but the number of buffers is {0}",
                      buffers.size());

    SmallVector<Byte> buffersSize;
    std::transform(buffers.begin(), buffers.end(), std::back_inserter(buffersSize), [](const auto buffer) {
        return buffer.getTotalAllocSize();
    });

    auto totalAvailableCMXSize = reservedMem.count() == 0 ? getTotalCMXSize(getOperation()).count()
                                                          : getTotalCMXFragmentationAwareSize(getOperation()).count();

    return vpux::VPU::calculateAlignedBuffersMemoryRequirement(getArch(getOperation()), buffersSize).count() +
                   reservedMem.count() <=
           totalAvailableCMXSize;
}

bool vpux::VPU::DynamicReshapeOp::fitIntoCMX(llvm::ArrayRef<vpux::NDTypeInterface> buffers) {
    return fitIntoCMX(buffers, Byte(0));
}

bool vpux::VPU::DynamicReshapeOp::supportCycleCostCalculation() {
    return false;
}
