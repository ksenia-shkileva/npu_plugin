//
// Copyright (C) 2022-2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/explicit_distribution_utils.hpp"
#include "vpux/compiler/dialect/VPU/utils/layout_utils.hpp"

#include "vpux/compiler/utils/attributes.hpp"

using namespace vpux;

namespace {

mlir::FailureOr<mlir::Type> inferElemType(VPU::AffineReshapeOpAdaptor affineReshapeOp, mlir::Type inputElemType) {
    const auto perAxisQType = inputElemType.dyn_cast_or_null<mlir::quant::UniformQuantizedPerAxisType>();
    if (perAxisQType == nullptr) {
        return inputElemType;
    }

    const auto inputQAxis = perAxisQType.getQuantizedDimension();

    const auto dimMapping = parseIntArrayOfArrayAttr<int64_t>(affineReshapeOp.getDimMapping());
    const auto outputShape = parseIntArrayAttr<int64_t>(affineReshapeOp.getShapeValue());
    const auto inputShape = getShape(affineReshapeOp.getInput()).raw();

    // get output dims for input Q axis
    const auto outputDims = dimMapping[inputQAxis];
    int64_t outQAxis = -1;
    int64_t inputQAxisSize = inputShape[inputQAxis];

    if (inputQAxisSize == 1) {
        // Per tensor, but must be per channel, do not handle it here
        return mlir::failure();
    }

    for (const auto& dim : outputDims) {
        if (inputQAxisSize == outputShape[dim]) {
            // firstly check that element is unique and others == 1
            if (std::find_if(outputDims.begin(), outputDims.end(), [&](int64_t elem) {
                    return (outputShape[elem] != 1 && outputShape[elem] != inputQAxisSize);
                }) != outputDims.end()) {
                return mlir::failure();
            }
            outQAxis = dim;
            break;
        }
    }

    if (outQAxis == -1) {
        return mlir::failure();
    }

    return mlir::quant::UniformQuantizedPerAxisType::get(
            perAxisQType.getFlags(), perAxisQType.getStorageType(), perAxisQType.getExpressedType(),
            perAxisQType.getScales(), perAxisQType.getZeroPoints(), static_cast<int32_t>(outQAxis),
            perAxisQType.getStorageTypeMin(), perAxisQType.getStorageTypeMax());
}

}  // namespace

mlir::LogicalResult vpux::VPU::AffineReshapeOp::inferReturnTypes(
        mlir::MLIRContext* ctx, std::optional<mlir::Location> optLoc, mlir::ValueRange operands,
        mlir::DictionaryAttr attrs, mlir::OpaqueProperties prop, mlir::RegionRange /*regions*/,
        mlir::SmallVectorImpl<mlir::Type>& inferredReturnTypes) {
    const auto loc = optLoc.value_or(mlir::UnknownLoc::get(ctx));

    VPU::AffineReshapeOpAdaptor affineReshape(operands, attrs, prop);
    if (mlir::failed(affineReshape.verify(loc))) {
        return mlir::failure();
    }

    const auto outShape = Shape(parseIntArrayAttr<int64_t>(affineReshape.getShapeValue()));
    const auto input = affineReshape.getInput();
    const auto inType = input.getType();
    const auto ndInType = inType.cast<vpux::NDTypeInterface>();
    const auto inOrder = DimsOrder::fromValue(input);

    const auto outputLayout = inferAffineReshapeOutputLayout(inOrder.toPermutation(), affineReshape.getDimMapping());
    if (mlir::failed(outputLayout)) {
        return mlir::failure();
    }

    auto typeComponents = TypeComponents().setShape(outShape).setDimsOrder(outputLayout.value());
    const auto elemTypeInferResult = inferElemType(affineReshape, ndInType.getElementType());
    if (mlir::succeeded(elemTypeInferResult)) {
        typeComponents = typeComponents.setElementType(elemTypeInferResult.value());
    }

    auto getOutputType = [&](NDTypeInterface type, const TypeComponents& components) -> NDTypeInterface {
        auto distributedType = type.dyn_cast<VPU::DistributedTensorType>();
        if (distributedType == nullptr ||
            !VPU::isDistributedAttrWithExplicitShapesAndOffsets(distributedType.getDistribution())) {
            return type.changeTypeComponents(components);
        }

        auto origDistribution = distributedType.getDistribution();
        auto distribWithExplicitAttr = VPU::getNonOverlappedDistributedAttr(
                outShape, origDistribution.getMode(), origDistribution.getNumTiles(), origDistribution.getNumClusters(),
                origDistribution.getAlignment(), origDistribution.getUniformDistributedSegments(), ctx);

        return distributedType.changeTypeComponentsForExplicitDistribution(components, distribWithExplicitAttr);
    };

    NDTypeInterface outType;
    if (auto sparseInputType = ndInType.dyn_cast<VPU::SparseTensorType>()) {
        const NDTypeInterface dataType = sparseInputType.getData();
        outType = VPU::SparseTensorType::get(getOutputType(dataType, typeComponents));
    } else {
        outType = getOutputType(ndInType, typeComponents);
    }
    inferredReturnTypes.push_back(outType);

    return mlir::success();
}

//
// DistributedCastOpInterface
//

mlir::FailureOr<VPU::DistributedTypeInterface> vpux::VPU::AffineReshapeOp::inferCastedDistOutput(
        VPU::DistributedTensorType inDistributedType) {
    if (inDistributedType == nullptr || inDistributedType.getDistribution() == nullptr) {
        return mlir::failure();
    }

    auto origDistribution = inDistributedType.getDistribution();
    // TODO: E-128707 - extend for other distribution modes
    if (origDistribution.getMode().getValue() != VPU::DistributionMode::DUPLICATED) {
        return mlir::failure();
    }

    const auto ctx = getContext();
    const auto dstType = getOutput().getType().cast<NDTypeInterface>();
    const auto outShape = dstType.getShape();
    const auto dstElemType = dstType.getElementType();

    if (!VPU::isDistributedAttrWithExplicitShapesAndOffsets(origDistribution)) {
        const auto typeComponents =
                TypeComponents().setShape(outShape).setDimsOrder(dstType.getDimsOrder()).setElementType(dstElemType);
        return inDistributedType.changeTypeComponents(typeComponents).cast<VPU::DistributedTypeInterface>();
    }

    const auto dstDimsOrderAttr = mlir::AffineMapAttr::get(dstType.getDimsOrder().toAffineMap(ctx));
    auto distribWithExplicitAttr = VPU::getNonOverlappedDistributedAttr(
            outShape, origDistribution.getMode(), origDistribution.getNumTiles(), origDistribution.getNumClusters(),
            origDistribution.getAlignment(), origDistribution.getUniformDistributedSegments(), ctx);

    return VPU::DistributedTensorType::get(ctx, outShape.raw(), dstElemType, dstDimsOrderAttr,
                                           inDistributedType.getMemSpace(), distribWithExplicitAttr)
            .cast<VPU::DistributedTypeInterface>();
}
