//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/conversion/passes/VPUMI40XX2VPUASM/symbolization_pattern.hpp"

namespace vpux {
namespace vpumi40xx2vpuasm {

class KernelDataRewriter : public VPUASMSymbolizationPattern<VPUMI40XX::DeclareKernelArgsOp> {
public:
    using Base::Base;
    mlir::LogicalResult symbolize(VPUMI40XX::DeclareKernelArgsOp op, SymbolMapper& mapper,
                                  mlir::ConversionPatternRewriter& rewriter) const override;
};

}  // namespace vpumi40xx2vpuasm
}  // namespace vpux
