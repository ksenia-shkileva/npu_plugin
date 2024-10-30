//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

//
// Backprop to data is itself convolution, with inputs/outputs/attributes transmogrified as
// follows.
//
//                          Forward   Backward
// "N" axis for data batch  0         0
// "C" axis for data batch  1         1
// "Co" axis for filters    0         0
// "Ci" axis for filters    1         1
// "N" axis for output      0         0
// "C" axis for output      1         1
// Data batch               x         delta
// Data batch shape         S_x       S_o
// Filters                  f         reverse(f) [on spatial axes]
// Filters shape            S_f       S_f
// Window movement strides  q_x       p_x
// Window dilation strides  p_f       p_f
// Padding below            a_x       (S_f - 1)p_f - a_x
// Padding above            b_x       (S_f - 1)p_f +
//                                      + ((a_x + (S_x - 1)p_x + b_x - (S_f - 1)p_f)
//                                         % q_x)
//                                      - b_x
// Data dilation strides    p_x       q_x
// Output shape             S_o       S_x
//
// To _validate_, we simply need to check/infer the output shape of the forward convolution,
// then check to make sure that the incoming delta has the same shape as the forward output.
//

#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/IE/utils/convolution_utils.hpp"

#include "vpux/compiler/dialect/const/ops.hpp"
#include "vpux/compiler/utils/attributes.hpp"
#include "vpux/compiler/utils/error.hpp"
#include "vpux/compiler/utils/infer_output_shape.hpp"

#include "openvino/op/group_conv.hpp"

using namespace vpux;

mlir::LogicalResult vpux::IE::TransposedConvolutionOp::inferReturnTypeComponents(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueShapeRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties prop, mlir::RegionRange,
        SmallVectorImpl<mlir::ShapedTypeComponents>& inferredReturnShapes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    IE::TransposedConvolutionOpAdaptor convBackpropData(operands, attrs, prop);
    if (mlir::failed(convBackpropData.verify(loc))) {
        return mlir::failure();
    }

    const auto inputShape = convBackpropData.getInput().getType().cast<mlir::ShapedType>().getShape();
    const auto featureType = convBackpropData.getInput().getType().cast<mlir::ShapedType>().getElementType();
    const auto outputShape = convBackpropData.getOutputShape();
    const auto filterShape = convBackpropData.getFilter().getType().cast<mlir::ShapedType>().getShape();

    const auto dataPaddingBelow = parseIntArrayAttr<int64_t>(convBackpropData.getPadsEnd());
    const auto dataPaddingAbove = parseIntArrayAttr<int64_t>(convBackpropData.getPadsBegin());
    const auto windowStrides = parseIntArrayAttr<int64_t>(convBackpropData.getStrides());
    const auto windowDilations = parseIntArrayAttr<int64_t>(convBackpropData.getDilations());
    const auto outputPadding = parseIntArrayAttr<int64_t>(convBackpropData.getOutputPadding());

    if (outputShape != nullptr) {
        const SmallVector<ov::Dimension> nDataShape(std::next(inputShape.begin(), 2), inputShape.end());
        const SmallVector<ov::Dimension> nFilterShape(std::next(filterShape.begin(), 2), filterShape.end());

        auto outputShapeConst = outputShape.getDefiningOp<Const::DeclareOp>();
        if (outputShapeConst == nullptr) {
            return errorAt(loc, "Only constant input is supported for output_shape");
        }

        const auto outputShapeContent = outputShapeConst.getContent();
        const auto outputShapeVals = outputShapeContent.getValues<int64_t>();

        SmallVector<int64_t> mlirOutputShape;
        mlirOutputShape.push_back(inputShape[Dims4D::Act::N.ind()]);
        mlirOutputShape.push_back(filterShape[0]);
        std::copy(outputShapeVals.begin(), outputShapeVals.end(), std::back_inserter(mlirOutputShape));

        if (convBackpropData.getOutputChannels().has_value()) {
            mlirOutputShape[Dims4D::Filter::OC.ind()] = convBackpropData.getOutputChannels().value();
        }

        inferredReturnShapes.emplace_back(mlirOutputShape, featureType);
    } else {
        auto mlirOutputShape =
                inferTransposedConvBackpropOutputShape(inputShape, filterShape, windowStrides, dataPaddingBelow,
                                                       dataPaddingAbove, windowDilations, outputPadding);

        if (convBackpropData.getOutputChannels().has_value()) {
            mlirOutputShape[Dims4D::Filter::OC.ind()] = convBackpropData.getOutputChannels().value();
        }
        inferredReturnShapes.emplace_back(mlirOutputShape, featureType);
    }

    return mlir::success();
}

void vpux::IE::TransposedConvolutionOp::getCanonicalizationPatterns(mlir::RewritePatternSet& patterns,
                                                                    mlir::MLIRContext* context) {
    patterns.add<FuseConvAndBias>(context);
}
