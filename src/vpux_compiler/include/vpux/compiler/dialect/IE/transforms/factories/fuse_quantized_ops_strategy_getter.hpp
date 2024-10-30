//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/core/interfaces/rewriter_pattern_strategies.hpp"

#include <mlir/Dialect/Func/IR/FuncOps.h>

namespace vpux::IE {

/*
   Find right class to get strategies for particular platform
*/
std::unique_ptr<IGreedilyPassStrategy> createFuseQuantizedOpsStrategy(mlir::func::FuncOp funcOp,
                                                                      const bool seOpsEnabled,
                                                                      const bool seExperimentalOpsEnabled);

}  // namespace vpux::IE
