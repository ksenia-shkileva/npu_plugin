//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/core/barrier_info.hpp"
#include "vpux/compiler/dialect/VPURT/IR/ops.hpp"

namespace vpux {
namespace VPURT {

size_t getMinEntry(const BarrierInfo::TaskSet& entries);
size_t getMaxEntry(const BarrierInfo::TaskSet& entries);

void postProcessBarrierOps(mlir::func::FuncOp func);
bool verifyBarrierSlots(mlir::func::FuncOp func, Logger log);
bool verifyOneWaitBarrierPerTask(mlir::func::FuncOp funcOp, Logger log);
void orderExecutionTasksAndBarriers(mlir::func::FuncOp funcOp, BarrierInfo& barrierInfo,
                                    bool orderByConsumption = false);

// TaskOp queue related utility functions
using TaskOpQueues = std::map<VPURT::TaskQueueType, SmallVector<uint32_t>>;
using TaskOpQueueIterator = std::map<VPURT::TaskQueueType, SmallVector<uint32_t>::iterator>;
TaskOpQueues getTaskOpQueues(mlir::func::FuncOp funcOp, BarrierInfo& barrierInfo,
                             std::optional<VPU::ExecutorKind> targetExecutorKind = std::nullopt);
TaskOpQueueIterator initializeTaskOpQueueIterators(TaskOpQueues& taskOpQueues);
bool allQueuesReachedEnd(const TaskOpQueueIterator& frontTasks, const TaskOpQueues& taskOpQueues);
bool allQueuesWaiting(const TaskOpQueueIterator& frontTasks, const TaskOpQueues& taskOpQueues,
                      BarrierInfo& barrierInfo);
SmallVector<size_t> findReadyOpsFromTaskOpQueues(TaskOpQueueIterator& frontTasks, const TaskOpQueues& taskOpQueues,
                                                 BarrierInfo& barrierInfo);

}  // namespace VPURT
}  // namespace vpux
