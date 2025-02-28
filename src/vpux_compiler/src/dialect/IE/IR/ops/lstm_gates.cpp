//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/IR/ops.hpp"

#include "vpux/compiler/utils/error.hpp"

using namespace vpux;

mlir::LogicalResult vpux::IE::LSTMGatesOp::inferReturnTypeComponents(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueShapeRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties prop, mlir::RegionRange,
        SmallVectorImpl<mlir::ShapedTypeComponents>& inferredReturnShapes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    IE::LSTMGatesOpAdaptor lstm(operands, attrs, prop);
    if (mlir::failed(lstm.verify(loc))) {
        return mlir::failure();
    }

    const auto inType = lstm.getInitialCellState().getType().cast<mlir::ShapedType>();

    inferredReturnShapes.emplace_back(inType.getShape(), inType.getElementType());  // outputHiddenState
    inferredReturnShapes.emplace_back(inType.getShape(), inType.getElementType());  // outputCellState

    return mlir::success();
}

//
// verify
//

mlir::LogicalResult vpux::IE::LSTMGatesOp::verify() {
    const auto gatesInputShape = getShape(getGatesInput()).raw();
    const auto initialCellStateShape = getShape(getInitialCellState()).raw();
    VPUX_THROW_UNLESS(initialCellStateShape.size() == 2 || initialCellStateShape.size() == 4,
                      "LSTMGatesOp requires the input shape size is 2 or 4, but here is {0}",
                      initialCellStateShape.size());

    const auto batchSize = gatesInputShape.size() == 2 ? initialCellStateShape[0] : initialCellStateShape[2];
    const auto hiddenSize = gatesInputShape.size() == 2 ? initialCellStateShape[1] : initialCellStateShape[3];

    if (gatesInputShape != ArrayRef<int64_t>({batchSize, 4 * hiddenSize}) &&
        gatesInputShape != ArrayRef<int64_t>({1, 1, batchSize, 4 * hiddenSize})) {
        return errorAt(*this,
                       "Incompatible input shapes. Expected gatesInput shape: [batch_size, 4*hidden_size], "
                       "initialCellState shape: [batch_size, hidden_size]. Got gatesInput shape: {0}, initialCellState "
                       "shape: {1}",
                       gatesInputShape, initialCellStateShape);
    }

    return mlir::success();
}
