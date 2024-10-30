//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/utils/attributes_utils.hpp"
#include "vpux/utils/core/checked_cast.hpp"

using namespace vpux;

mlir::LogicalResult vpux::IE::SoftMaxOp::inferReturnTypeComponents(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueShapeRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties prop, mlir::RegionRange,
        SmallVectorImpl<mlir::ShapedTypeComponents>& inferredReturnShapes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    IE::SoftMaxOpAdaptor softMax(operands, attrs, prop);
    if (mlir::failed(softMax.verify(loc))) {
        return mlir::failure();
    }

    const auto inType = mlir::cast<mlir::RankedTensorType>(softMax.getInput().getType());
    const auto outDesc = vpux::getTensorAttr(inType);
    inferredReturnShapes.emplace_back(inType.getShape(), inType.getElementType(), outDesc);

    return mlir::success();
}

mlir::OpFoldResult vpux::IE::SoftMaxOp::fold(FoldAdaptor) {
    const auto inType = getInput().getType().cast<mlir::ShapedType>();
    const auto inShape = inType.getShape();
    const auto inRank = inType.getRank();

    auto axis = checked_cast<int64_t>(getAxisInd());

    if (axis < 0) {
        axis += inRank;
    }

    VPUX_THROW_UNLESS(axis >= 0 && axis < inRank, "Wrong SoftMax axis {0}", axis);

    if (inShape[axis] > 1) {
        return nullptr;
    }

    const auto valueType = mlir::RankedTensorType::get(inShape, mlir::Float32Type::get(getContext()));
    return Const::ContentAttr::transform(mlir::DenseElementsAttr::get(valueType, 1.0f))
            .castElemType(getOutput().getType().cast<mlir::ShapedType>().getElementType())
            .get();
}

//
// LegalizeAxisInd
//

namespace {

class LegalizeAxisInd final : public mlir::OpRewritePattern<IE::SoftMaxOp> {
public:
    using mlir::OpRewritePattern<IE::SoftMaxOp>::OpRewritePattern;

public:
    mlir::LogicalResult matchAndRewrite(IE::SoftMaxOp softmaxOp, mlir::PatternRewriter& rewriter) const final;
};

mlir::LogicalResult LegalizeAxisInd::matchAndRewrite(IE::SoftMaxOp softmaxOp, mlir::PatternRewriter& rewriter) const {
    auto inputType = softmaxOp.getInput().getType().cast<vpux::NDTypeInterface>();
    int64_t axis = softmaxOp.getAxisInd();

    if (axis >= 0) {
        return mlir::failure();
    }

    int64_t legalizeAxis = vpux::getPositiveAxisInd(softmaxOp.getAxisIndAttr(), inputType.getRank());
    const auto legalizeAxisAttr = getIntAttr(rewriter.getContext(), legalizeAxis);

    rewriter.replaceOpWithNewOp<IE::SoftMaxOp>(softmaxOp, softmaxOp.getInput(), legalizeAxisAttr, nullptr);
    return mlir::success();
}

}  // namespace

//
// getCanonicalizationPatterns
//

void vpux::IE::SoftMaxOp::getCanonicalizationPatterns(mlir::RewritePatternSet& patterns, mlir::MLIRContext* context) {
    patterns.add<LegalizeAxisInd>(context);
}
