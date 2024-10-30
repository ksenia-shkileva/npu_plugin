//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/utils/reshape_utils.hpp"

namespace {
struct MinDimension {
    std::size_t& shapeIdx;
    llvm::ArrayRef<int64_t> shape;
    int64_t largeDimQuotient;

    MinDimension(std::size_t& shapeIdx, llvm::ArrayRef<int64_t> shape, const int64_t largeDimQuotient)
            : shapeIdx(shapeIdx), shape(shape), largeDimQuotient(largeDimQuotient){};
};
}  // namespace

namespace vpux {
namespace IE {

void handleConsecutiveOnes(ArrayRef<int64_t> inShape, ArrayRef<int64_t> outShape, std::size_t& startIn,
                           std::size_t& startOut, SmallVector<SmallVector<int64_t>>& reassociationVec) {
    std::size_t endIn = startIn;
    while (endIn < inShape.size() && inShape[endIn] == 1) {
        endIn++;
    }

    std::size_t endOut = startOut;
    while (endOut < outShape.size() && outShape[endOut] == 1) {
        endOut++;
    }

    for (; startIn < endIn && startOut < endOut; ++startIn, ++startOut) {
        reassociationVec[startIn].push_back(static_cast<int64_t>(startOut));
    }

    while (startIn < endIn) {
        reassociationVec[startIn].push_back(static_cast<int64_t>(startOut - 1));
        startIn++;
    }

    while (startOut < endOut) {
        reassociationVec[startIn - 1].push_back(static_cast<int64_t>(startOut));
        startOut++;
    }
}

mlir::FailureOr<SmallVector<SmallVector<int64_t>>> createReassociationMap(ArrayRef<int64_t> inShape,
                                                                          ArrayRef<int64_t> outShape,
                                                                          bool isExtension) {
    const auto inSize = inShape.size();
    const auto outSize = outShape.size();

    const auto nextDimIsOne = [](ArrayRef<int64_t> shape, const std::size_t index) -> bool {
        return index + 1 < shape.size() && shape[index + 1] == 1;
    };

    const auto remainDimAreOnes = [](ArrayRef<int64_t> shape, const std::size_t index) -> bool {
        if (index + 1 > shape.size()) {
            return false;
        }
        for (auto remainIndex = index; remainIndex < shape.size(); remainIndex++) {
            if (shape[remainIndex] != 1) {
                return false;
            }
        }
        return true;
    };

    SmallVector<SmallVector<int64_t>> reassociationVec(inSize);
    size_t inIdx = 0, outIdx = 0;
    for (; inIdx < inSize && outIdx < outSize; ++inIdx, ++outIdx) {
        if (inShape[inIdx] == 1 && outShape[outIdx] == 1) {
            if (isExtension) {
                while (inIdx < inSize && outIdx < outSize && inShape[inIdx] == 1 && outShape[outIdx] == 1) {
                    reassociationVec[inIdx++].push_back(static_cast<int64_t>(outIdx++));
                }
            } else {
                // Pair dims equal to 1 that have corresponding dims in the other shape
                handleConsecutiveOnes(inShape, outShape, inIdx, outIdx, reassociationVec);
            }

            if (inIdx >= inSize || outIdx >= outSize) {
                break;
            }
        }

        // If both dims are equal, pick the one that has a dim of 1 after it. If there is no corresponding dim equal to
        // 1 in the other shape, the mapping dim_large = 1 x dim_small will be added. Without that extra condition,
        // there could be cases where that extra 1 remains floating, leading the algorithm to decide that there is no
        // valid mapping between shapes.
        const bool isInputSmallerDim = inShape[inIdx] < outShape[outIdx] ||
                                       (inShape[inIdx] == outShape[outIdx] && nextDimIsOne(inShape, inIdx));
        auto minimum = isInputSmallerDim ? MinDimension(inIdx, inShape, outShape[outIdx])
                                         : MinDimension(outIdx, outShape, inShape[inIdx]);

        do {
            if (minimum.largeDimQuotient % minimum.shape[minimum.shapeIdx] != 0)
                return mlir::failure();

            reassociationVec[inIdx].push_back(static_cast<int64_t>(outIdx));

            minimum.largeDimQuotient /= minimum.shape[minimum.shapeIdx];

            if (minimum.largeDimQuotient == 1) {
                if (isExtension) {
                    if (!(nextDimIsOne(minimum.shape, minimum.shapeIdx) &&
                          (minimum.shapeIdx + 1 == minimum.shape.size() - 1))) {
                        // Exit loop unless the next dim is 1 and is the last dimesnion
                        break;
                    }
                } else if (!nextDimIsOne(minimum.shape, minimum.shapeIdx) ||
                           (nextDimIsOne(inShape, inIdx) && nextDimIsOne(outShape, outIdx))) {
                    // Exit loop if the next dim isn't 1 or if there are 1s on next dim of both shapes
                    break;
                }
            }

            ++minimum.shapeIdx;
        } while (minimum.shapeIdx < minimum.shape.size());
    }

    // When the input is a scalar, a ReshapeOp will be inserted to convert it to a tensor.
    // Converting ReshapeOp to AffineReshape will cause rank issue in AdjustLayouts.
    if (inSize == 0) {
        return mlir::failure();
    }

    // In the specific case, the outputShape last dim == 1, the reassociationVec is
    // [[0], [1], [2], [2]], the reassociationVec could be updated to: [[0], [1], [2], [2,3]]
    if (inIdx == inSize && remainDimAreOnes(outShape, outIdx)) {
        for (auto outIdxGap = outIdx; outIdxGap < outSize; outIdxGap++) {
            reassociationVec[inSize - 1].push_back(static_cast<int64_t>(outIdxGap));
        }
        return reassociationVec;
    }

    // One of the shapes has trailing 1s that cannot be the result of decomposing the last dim of the other shape
    if (inIdx < inSize || outIdx < outSize) {
        return mlir::failure();
    }

    return reassociationVec;
}

// Note: When having dims equal to 1 in one of the shapes that do not have a corresponding 1 in the other shape, there
// might be multiple dim associations possible.
// E.g.: 1 x 2 x 2 x 1 x 2 x 3 -> 1 x 4 x 6 has 2 possible mappings:
//      {0} -> {0}, {1, 2, 3} -> {1}, {4, 5} -> {2} (this one is computed by the fcn below)
//      {0} -> {0}, {1, 2} -> {1}, {3, 4, 5} -> {2} (this one is computed by the extended fcn below)
mlir::FailureOr<SmallVector<SmallVector<int64_t>>> getReassociationMap(ArrayRef<int64_t> inShape,
                                                                       ArrayRef<int64_t> outShape) {
    return createReassociationMap(inShape, outShape, false);
}

// The dims that equal to 1 are preferred to be associated with the following dimensions.
// E.g.
//  inShape:     1 x 512 x 1 x 1500
//               |   |\     \  |
//               |   | \     \ |
//               |   |  \     \|
//  outShape:    1 x 1 x 512 x 1500
mlir::FailureOr<SmallVector<SmallVector<int64_t>>> getReassociationMapExtension(ArrayRef<int64_t> inShape,
                                                                                ArrayRef<int64_t> outShape) {
    return createReassociationMap(inShape, outShape, true);
}

bool isNotDimExpansionReshape(ShapeRef origShape, ShapeRef reshapeShape) {
    auto getNonOneDims = [](ShapeRef shape) {
        Shape resultShape;
        llvm::copy_if(shape, std::back_inserter(resultShape), [](int64_t elem) {
            return elem != 1;
        });
        return resultShape;
    };
    return getNonOneDims(origShape) != getNonOneDims(reshapeShape);
}

bool isNotDimShrinkReshape(ShapeRef origShape, ShapeRef reshapeShape) {
    return origShape.size() <= reshapeShape.size();
}

IE::ShapeCastOp buildShapeCast(mlir::Location loc, mlir::Value input, ArrayRef<int64_t> targetShape,
                               mlir::PatternRewriter& rewriter) {
    const auto ctx = rewriter.getContext();
    const auto srcType = input.getType().cast<vpux::NDTypeInterface>();
    const auto dstType = srcType.changeShape(ShapeRef(targetShape));
    const auto targetShapeAttr = getIntArrayAttr(ctx, targetShape);
    return rewriter.create<IE::ShapeCastOp>(loc, dstType, input, targetShapeAttr);
}

bool isEligibleToFoldStrideKernel(vpux::NDTypeInterface inputType, vpux::NDTypeInterface outputType, int64_t kernelX,
                                  int64_t strideX, int64_t strideY, int64_t inAlignment, int64_t outAlignment,
                                  const Logger& log) {
    auto inDimOrder = inputType.getDimsOrder();
    if (DimsOrder::NHWC != inDimOrder) {
        return false;
    }

    if ((1 == strideX) || (kernelX > strideX)) {
        return false;
    }

    // Workaround. In case of [1, 4] strides, pass returns innacurate results. Follow-up ticket
    // E#141091
    if ((4 == strideX) && (1 == strideY)) {
        return false;
    }

    auto inputShape = inputType.getShape();
    if (inputShape[Dims4D::Act::W] % strideX) {
        return false;
    }

    auto outputShape = outputType.getShape();
    const auto IC = inputShape[Dims4D::Act::C];
    const auto OC = outputShape[Dims4D::Act::C];
    if ((IC % inAlignment) == 0 && (OC % outAlignment) == 0) {
        log.trace("The input/output channels are already aligned");
        return false;
    }

    return true;
}

Shape getNewShapeAfterStrideFolding(ShapeRef origShape, int64_t SX) {
    Shape newShape(origShape.raw());
    newShape[Dims4D::Act::W] /= SX;
    newShape[Dims4D::Act::C] *= SX;

    return newShape;
}

}  // namespace IE
}  // namespace vpux
