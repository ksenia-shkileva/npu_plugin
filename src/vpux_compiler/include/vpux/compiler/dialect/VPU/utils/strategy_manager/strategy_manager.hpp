//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/dialect/IE/utils/resources.hpp"
#include "vpux/compiler/dialect/VPU/IR/attributes.hpp"
#include "vpux/compiler/dialect/VPU/IR/ops.hpp"
#include "vpux/compiler/dialect/VPU/utils/sibling_ops_analysis.hpp"
#include "vpux/compiler/dialect/VPU/utils/strategy_manager/subgraph_optimizer.hpp"
#include "vpux/utils/core/checked_cast.hpp"

namespace vpux {
namespace VPU {
//
// StrategyManager
//

// Higher level strategy manager class
// Its current purpose is to globally assign strategies
// In future it may have methods for finding sub-graphs
// and other strategy related utilities
class StrategyManager final {
public:
    explicit StrategyManager(mlir::func::FuncOp func, int64_t numTiles, bool enablePrefetchTiling, Logger log,
                             SiblingOpsAnalysis& siblingsOpsAnalysis);

public:
    void assignMultiClusterStrategy(bool enableMultiClusterForSWLayer);
    void optimizeMulticlusterStrategy();
    void removeTemporaryMulticlusterStrategy();

private:
    mlir::func::FuncOp _func;
    int64_t _numTiles;
    Logger _log;
    LayerCostModel _costModel;
    SubgraphOptimizer _optimizer;
    SiblingOpsAnalysis& _siblingsOpsAnalysis;
};
}  // namespace VPU
}  // namespace vpux
