//
// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/VPU/IR/attributes.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/manual_strategy_utils.hpp"

#include <llvm/Support/JSON.h>

namespace vpux {
namespace VPU {

llvm::Expected<llvm::json::Value> readManualStrategyJSON(StringRef fileName);
void writeManualStrategyJSON(StringRef fileName, const llvm::json::Value& json);

llvm::json::Value convertAttrToJSON(mlir::Attribute attr);
void createStrategyJSONFromOperations(llvm::json::Value& json,
                                      llvm::MapVector<mlir::Location, mlir::Operation*>& operations,
                                      DenseMap<StringRef, StringRef>& strategyAttributes);
mlir::Attribute convertJSONToAttr(mlir::Attribute oldAttr, const llvm::json::Value& newAttrVal);
void overwriteManualStrategy(llvm::json::Value& manualStrategy,
                             llvm::MapVector<mlir::Location, mlir::Operation*>& operations);
void updateTilingStrategyInJSONForOperations(llvm::json::Value& json,
                                             llvm::MapVector<mlir::Location, mlir::Operation*>& operations);

void saveMCSideLoadStrategyToFile(mlir::func::FuncOp func, StringRef strategyJsonPath,
                                  const mlir::DenseMap<mlir::Operation*, size_t>& opToHash, StringRef modelHash);

}  // namespace VPU
}  // namespace vpux
