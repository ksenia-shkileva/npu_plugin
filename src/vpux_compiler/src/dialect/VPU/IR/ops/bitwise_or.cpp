//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/utils/shape_infer.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"

#include "vpux/utils/core/checked_cast.hpp"

using namespace vpux;

mlir::LogicalResult vpux::VPU::BitwiseOrOp::inferReturnTypes(mlir::MLIRContext* ctx,
                                                             std::optional<mlir::Location> optLoc,
                                                             mlir::ValueRange operands, mlir::DictionaryAttr attrs,
                                                             mlir::OpaqueProperties prop, mlir::RegionRange /*regions*/,
                                                             mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::BitwiseOrOpAdaptor bitwiseOr(operands, attrs, prop);
    if (mlir::failed(bitwiseOr.verify(loc))) {
        return mlir::failure();
    }

    const auto in1Type = bitwiseOr.getInput1().getType().cast<vpux::NDTypeInterface>();
    const auto in2Type = bitwiseOr.getInput2().getType().cast<vpux::NDTypeInterface>();

    const auto outShapeRes = IE::broadcastEltwiseShape(in1Type.getShape().raw(), in2Type.getShape().raw(),
                                                       bitwiseOr.getAutoBroadcast(), loc);

    if (mlir::succeeded(outShapeRes)) {
        const auto outType = in1Type.changeShape(Shape(outShapeRes.value()));
        inferredReturnTypes.push_back(outType);
    }

    return mlir::success();
}
