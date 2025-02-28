//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/init.hpp"

#include "vpux/compiler/NPU37XX/dialect/NPUReg37XX/ops.hpp"
#include "vpux/compiler/NPU40XX/dialect/ELF/ops.hpp"
#include "vpux/compiler/NPU40XX/dialect/NPUReg40XX/ops.hpp"
#include "vpux/compiler/conversion/passes/VPU2VPUIP/bufferizable_ops_interface.hpp"
#include "vpux/compiler/dialect/ELFNPU37XX/ops.hpp"
#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/IERT/ops.hpp"
#include "vpux/compiler/dialect/VPU/IR/attributes.hpp"
#include "vpux/compiler/dialect/VPU/IR/dialect.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops_interfaces.hpp"
#include "vpux/compiler/dialect/VPUASM/dialect.hpp"
#include "vpux/compiler/dialect/VPUIP/IR/dialect.hpp"
#include "vpux/compiler/dialect/VPUIP/IR/ops.hpp"
#include "vpux/compiler/dialect/VPUIPDPU/dialect.hpp"
#include "vpux/compiler/dialect/VPUMI37XX/ops.hpp"
#include "vpux/compiler/dialect/VPUMI40XX/dialect.hpp"
#include "vpux/compiler/dialect/VPURT/IR/ops.hpp"
#include "vpux/compiler/dialect/VPURegMapped/ops.hpp"
#include "vpux/compiler/dialect/const/ops.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/Dialect/Affine/IR/AffineOps.h>
#include <mlir/Dialect/Async/IR/Async.h>
#include <mlir/Dialect/ControlFlow/IR/ControlFlow.h>
#include <mlir/Dialect/LLVMIR/LLVMDialect.h>
#include <mlir/Dialect/Math/IR/Math.h>
#include <mlir/Dialect/MemRef/IR/MemRef.h>
#include <mlir/Dialect/Quant/QuantOps.h>
#include <mlir/Dialect/Quant/QuantTypes.h>
#include <mlir/Dialect/Tensor/IR/Tensor.h>
#include <mlir/IR/BuiltinDialect.h>
#include <mlir/IR/BuiltinTypes.h>
#include <mlir/Transforms/BufferizationUtils.h>

using namespace vpux;

//
// registerDialects
//

namespace {

class MemRefElementTypeModel final : public mlir::MemRefElementTypeInterface::FallbackModel<MemRefElementTypeModel> {};

struct CustomBuiltinBufferizerInterface : mlir::DialectBufferizerInterface {
    using mlir::DialectBufferizerInterface::DialectBufferizerInterface;

    mlir::Type getTensorTypeFromMemRefType(mlir::Type type) const final {
        // ensures encoding is correct in the builtin ranked tensor
        return reconstructTensorType(type);
    }
};

}  // namespace

void vpux::registerDialects(mlir::DialectRegistry& registry) {
    registry.insert<vpux::Const::ConstDialect,                //
                    vpux::IE::IEDialect,                      //
                    vpux::VPU::VPUDialect,                    //
                    vpux::IERT::IERTDialect,                  //
                    vpux::VPUIP::VPUIPDialect,                //
                    vpux::VPUIPDPU::VPUIPDPUDialect,          //
                    vpux::VPURT::VPURTDialect,                //
                    vpux::VPUMI37XX::VPUMI37XXDialect,        //
                    vpux::VPUMI40XX::VPUMI40XXDialect,        //
                    vpux::VPUASM::VPUASMDialect,              //
                    vpux::VPURegMapped::VPURegMappedDialect,  //
                    vpux::ELF::ELFDialect,                    //
                    vpux::NPUReg37XX::NPUReg37XXDialect,      //
                    vpux::NPUReg40XX::NPUReg40XXDialect,      //
                    vpux::ELFNPU37XX::ELFNPU37XXDialect>();

    registry.insert<mlir::func::FuncDialect,           //
                    mlir::async::AsyncDialect,         //
                    mlir::memref::MemRefDialect,       //
                    mlir::quant::QuantizationDialect,  //
                    mlir::tensor::TensorDialect,       //
                    mlir::arith::ArithDialect,         //
                    mlir::affine::AffineDialect,       //
                    mlir::scf::SCFDialect,             //
                    mlir::math::MathDialect,           //
                    mlir::cf::ControlFlowDialect,      //
                    mlir::LLVM::LLVMDialect>();
}

void vpux::registerCommonInterfaces(mlir::DialectRegistry& registry, bool enableDummyOp) {
    registry.addExtension(+[](mlir::MLIRContext* ctx, mlir::quant::QuantizationDialect*) {
        mlir::quant::AnyQuantizedType::attachInterface<MemRefElementTypeModel>(*ctx);
        mlir::quant::UniformQuantizedType::attachInterface<MemRefElementTypeModel>(*ctx);
        mlir::quant::UniformQuantizedPerAxisType::attachInterface<MemRefElementTypeModel>(*ctx);
        mlir::quant::CalibratedQuantizedType::attachInterface<MemRefElementTypeModel>(*ctx);
    });
    Const::ConstDialect::setupExtraInterfaces(registry);
    IERT::IERTDialect::setupExtraInterfaces(registry);
    VPUIP::VPUIPDialect::setupExtraInterfaces(registry);
    VPU::registerAlignedChannelsOpInterfacesVPU(registry);

    if (enableDummyOp) {
        VPUIP::VPUIPDialect::setupExtraInterfacesAdditional(registry);
    }

    registry.addExtension(+[](mlir::MLIRContext*, mlir::BuiltinDialect* dialect) {
        dialect->addInterfaces<CustomBuiltinBufferizerInterface>();
    });
}
