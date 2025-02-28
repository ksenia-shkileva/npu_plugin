//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/IE/IR/ops_interfaces.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops_interfaces.hpp"
#include "vpux/compiler/utils/error.hpp"

using namespace vpux;

namespace {

template <class MainOpType>
class AlignedChannelsOpModel final :
        public IE::AlignedChannelsOpInterface::ExternalModel<AlignedChannelsOpModel<MainOpType>, MainOpType> {
public:
    mlir::LogicalResult verifyChannels(mlir::Operation* op) const {
        auto arch = VPU::getArch(op);
        return mlir::success(vpux::VPU::NCEInvariant::isInputActTypeSupported(
                                     arch, op->getOperand(0).getType().template cast<vpux::NDTypeInterface>(),
                                     getInputChannelAlignment(op), false) &&
                             vpux::VPU::NCEInvariant::isOutputActTypeSupported(
                                     op->getResult(0).getType().template cast<vpux::NDTypeInterface>(),
                                     getOutputChannelAlignment(op)));
    }

    int64_t getInputChannelAlignment(mlir::Operation* op) const {
        const auto inputType = op->getOperand(0).getType().cast<vpux::NDTypeInterface>();
        return VPU::NCEInvariant::getAlignment(inputType.getElementType());
    }
    int64_t getOutputChannelAlignment(mlir::Operation* op) const {
        const auto outputType = op->getResult(0).getType().cast<vpux::NDTypeInterface>();
        return VPU::NCEInvariant::getAlignment(outputType.getElementType());
    }
};

class AlignedChannelsCompressConvOpModel final :
        public IE::AlignedChannelsOpInterface::ExternalModel<AlignedChannelsCompressConvOpModel,
                                                             VPU::NCECompressConvolutionOp> {
public:
    mlir::LogicalResult verifyChannels(mlir::Operation* op) const {
        auto arch = VPU::getArch(op);
        return mlir::success(vpux::VPU::NCEInvariant::isInputActTypeSupported(
                                     arch, op->getOperand(0).getType().template cast<vpux::NDTypeInterface>(),
                                     getInputChannelAlignment(op), true) &&
                             vpux::VPU::NCEInvariant::isOutputActTypeSupported(
                                     op->getResult(0).getType().template cast<vpux::NDTypeInterface>(),
                                     getOutputChannelAlignment(op)));
    }

    int64_t getInputChannelAlignment(mlir::Operation*) const {
        return vpux::VPU::NCEInvariant::VPU_COMPRESSED_INPUT_CHANNEL_NUM;
    }
    int64_t getOutputChannelAlignment(mlir::Operation* op) const {
        const auto outputType = op->getResult(0).getType().cast<vpux::NDTypeInterface>();
        return VPU::NCEInvariant::getAlignment(outputType.getElementType());
    }
};

class AlignedChannelsPermuteOpModel final :
        public IE::AlignedChannelsOpInterface::ExternalModel<AlignedChannelsPermuteOpModel, VPU::NCEPermuteOp> {
public:
    mlir::LogicalResult verifyChannels(mlir::Operation* op) const {
        // We check width here because in following passes a Reorder layer will be added that will generate NWCH order
        const auto outType = op->getResult(0).getType().cast<NDTypeInterface>();
        const auto inType = op->getOperand(0).getType().cast<NDTypeInterface>();
        if (outType.getRank() != 4 || inType.getRank() != 4) {
            return errorAt(op, "Output activation has unsupported rank: input '{0}' , output '{1}' ", inType.getRank(),
                           outType.getRank());
        }
        const auto outAlignment = getOutputChannelAlignment(op);
        const auto OW = outType.getShape()[Dims4D::Act::W];
        if (OW % outAlignment != 0) {
            return errorAt(op, "Output width '{0}' is not aligned to '{1}'", OW, outAlignment);
        }
        const auto inAlignment = getInputChannelAlignment(op);
        const auto IW = inType.getShape()[Dims4D::Act::W];
        if (IW % inAlignment != 0) {
            return errorAt(op, "Input width '{0}' is not aligned to '{1}'", IW, inAlignment);
        }

        return mlir::success();
    }

    int64_t getInputChannelAlignment(mlir::Operation* op) const {
        const auto inputType = op->getOperand(0).getType().cast<vpux::NDTypeInterface>();
        return VPU::NCEInvariant::getAlignment(inputType.getElementType());
    }
    int64_t getOutputChannelAlignment(mlir::Operation* op) const {
        const auto outputType = op->getResult(0).getType().cast<vpux::NDTypeInterface>();
        return VPU::NCEInvariant::getAlignment(outputType.getElementType());
    }
};

}  // namespace

void vpux::VPU::registerAlignedChannelsOpInterfacesVPU(mlir::DialectRegistry& registry) {
    registry.addExtension(+[](mlir::MLIRContext* ctx, VPU::VPUDialect*) {
        VPU::NCEConvolutionOp::attachInterface<AlignedChannelsOpModel<VPU::NCEConvolutionOp>>(*ctx);
        VPU::NCEDepthConvolutionOp::attachInterface<AlignedChannelsOpModel<VPU::NCEDepthConvolutionOp>>(*ctx);
        VPU::NCEMaxPoolOp::attachInterface<AlignedChannelsOpModel<VPU::NCEMaxPoolOp>>(*ctx);
        VPU::NCEAveragePoolOp::attachInterface<AlignedChannelsOpModel<VPU::NCEAveragePoolOp>>(*ctx);
        VPU::NCEEltwiseOp::attachInterface<AlignedChannelsOpModel<VPU::NCEEltwiseOp>>(*ctx);
        VPU::NCEPermuteOp::attachInterface<AlignedChannelsPermuteOpModel>(*ctx);
        VPU::NCEInterpolateOp::attachInterface<AlignedChannelsOpModel<VPU::NCEInterpolateOp>>(*ctx);
        VPU::NCEMatMulOp::attachInterface<AlignedChannelsOpModel<VPU::NCEMatMulOp>>(*ctx);
        VPU::NCECompressConvolutionOp::attachInterface<AlignedChannelsCompressConvOpModel>(*ctx);
        VPU::NCEMatMulOp::attachInterface<AlignedChannelsOpModel<VPU::NCEMatMulOp>>(*ctx);
    });
}
