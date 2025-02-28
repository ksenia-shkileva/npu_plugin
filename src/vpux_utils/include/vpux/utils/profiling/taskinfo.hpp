//
// Copyright (C) 2022-2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// Profiling parser public interface

#pragma once

#include <cstdint>
#include <cstring>
#include <tuple>
#include <vector>

namespace vpux::profiling {

struct LayerInfo {
    char name[256];
    char layer_type[50];
    enum layer_status_t { NOT_RUN, OPTIMIZED_OUT, EXECUTED };
    layer_status_t status;
    uint64_t start_time_ns;        ///< Absolute start time
    uint64_t duration_ns;          ///< Total duration (from start time until last compute task completed)
    uint32_t layer_id = -1;        ///< Not used
    uint64_t fused_layer_id = -1;  ///< Not used
    // Aggregate compute time  (aka. "CPU" time, will include DPU, SW, DMA)
    uint64_t dpu_ns = 0;
    uint64_t sw_ns = 0;
    uint64_t dma_ns = 0;
};

// Size must match L0-ext ze_profiling_layer_info
static_assert(sizeof(LayerInfo) == 368);

struct TaskInfo {
    char name[256];
    char layer_type[50];
    enum class ExecType { NONE, DPU, SW, DMA, UPA, M2I };
    ExecType exec_type;
    uint64_t start_time_ns;
    uint64_t duration_ns;
    uint32_t active_cycles = 0;
    uint32_t stall_cycles = 0;
    uint32_t task_id = -1;
    uint32_t parent_layer_id = -1;  ///< Not used
};

// Size must match L0-ext ze_profiling_task_info
static_assert(sizeof(TaskInfo) == 344);

enum class FreqStatus { UNKNOWN, VALID, INVALID, SIM };
constexpr double UNINITIALIZED_FREQUENCY_VALUE = -1;

struct FreqInfo {
    double freqMHz = UNINITIALIZED_FREQUENCY_VALUE;
    FreqStatus freqStatus = FreqStatus::UNKNOWN;
};

struct ProfInfo {
    std::vector<TaskInfo> tasks;
    std::vector<LayerInfo> layers;
    FreqInfo dpuFreq;
};

template <typename T>
bool profilingTaskStartTimeComparator(const T& a, const T& b) {
    const auto namesCompareResult = std::strcmp(a.name, b.name);
    return std::forward_as_tuple(a.start_time_ns, namesCompareResult, b.duration_ns) <
           std::forward_as_tuple(b.start_time_ns, 0, a.duration_ns);
}

}  // namespace vpux::profiling
