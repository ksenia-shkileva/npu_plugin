//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-translate --vpu-arch=%arch% --export-VPUIP -o %t %data_path_npu%/profiling-37XX.mlir.txt
// RUN: prof_parser -b %t -p %data_path_npu%/profiling-0-37XX.bin -f json | FileCheck %s
// REQUIRES: arch-NPU37XX

// CHECK: {"traceEvents":[
// CHECK-NEXT: {"name": "process_name", "ph": "M", "pid":0, "args": {"name" : "DMA"}},
// CHECK-NEXT: {"name": "process_sort_index", "ph": "M", "pid":0, "args": {"sort_index" : "0"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":0, "tid":0, "args": {"name" : "DMA"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":0, "tid":1, "args": {"name" : "DMA"}},
// CHECK-NEXT: {"name": "process_name", "ph": "M", "pid":1, "args": {"name" : "Cluster (0)"}},
// CHECK-NEXT: {"name": "process_sort_index", "ph": "M", "pid":1, "args": {"sort_index" : "1"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":1, "tid":0, "args": {"name" : "DPU"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":1, "tid":1, "args": {"name" : "SW / Shave"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":1, "tid":2, "args": {"name" : "SW / Shave"}},
// CHECK-NEXT: {"name": "process_name", "ph": "M", "pid":2, "args": {"name" : "Cluster (1)"}},
// CHECK-NEXT: {"name": "process_sort_index", "ph": "M", "pid":2, "args": {"sort_index" : "2"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":2, "tid":0, "args": {"name" : "DPU"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":2, "tid":1, "args": {"name" : "SW / Shave"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":2, "tid":2, "args": {"name" : "SW / Shave"}},
// CHECK-NEXT: {"name": "process_name", "ph": "M", "pid":3, "args": {"name" : "Layers"}},
// CHECK-NEXT: {"name": "process_sort_index", "ph": "M", "pid":3, "args": {"sort_index" : "3"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":3, "tid":0, "args": {"name" : "Layers"}},
// CHECK-NEXT: {"name": "thread_name", "ph": "M", "pid":3, "tid":1, "args": {"name" : "Layers"}},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_0", "cat":"DMA", "ph":"X", "ts":0.000, "dur":0.859, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_0", "cat":"DMA", "ph":"X", "ts":1.093, "dur":0.885, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_expand_copy_3_2/_cluster_0", "cat":"DMA", "ph":"X", "ts":2.213, "dur":0.546, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_1", "cat":"DMA", "ph":"X", "ts":3.776, "dur":0.859, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_1", "cat":"DMA", "ph":"X", "ts":4.869, "dur":0.911, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_expand_copy_3_2/_cluster_1", "cat":"DMA", "ph":"X", "ts":6.015, "dur":0.546, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_0", "cat":"DMA", "ph":"X", "ts":25.729, "dur":0.546, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_1", "cat":"DMA", "ph":"X", "ts":25.885, "dur":0.234, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_1", "cat":"DMA", "ph":"X", "ts":26.562, "dur":0.416, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/_cluster_0", "cat":"DMA", "ph":"X", "ts":26.718, "dur":0.416, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_cluster_1", "cat":"DMA", "ph":"X", "ts":27.369, "dur":0.859, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_cluster_0", "cat":"DMA", "ph":"X", "ts":27.526, "dur":0.989, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_fused_constant/_fused_tile", "cat":"DMA", "ph":"X", "ts":28.750, "dur":0.651, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_cluster_1", "cat":"DMA", "ph":"X", "ts":30.963, "dur":2.864, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_cluster_0", "cat":"DMA", "ph":"X", "ts":31.119, "dur":2.552, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_cluster_0", "cat":"DMA", "ph":"X", "ts":34.062, "dur":2.656, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/_cluster_1", "cat":"DMA", "ph":"X", "ts":34.218, "dur":2.656, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"conv2/WithoutBiases?t_Convolution/_fused_constant/_fused_tile", "cat":"DMA", "ph":"X", "ts":37.031, "dur":2.500, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_1", "cat":"DMA", "ph":"X", "ts":72.369, "dur":0.963, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_0", "cat":"DMA", "ph":"X", "ts":72.526, "dur":0.963, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_1", "cat":"DMA", "ph":"X", "ts":73.645, "dur":0.703, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_0", "cat":"DMA", "ph":"X", "ts":73.802, "dur":0.703, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_1", "cat":"DMA", "ph":"X", "ts":74.739, "dur":1.067, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_0", "cat":"DMA", "ph":"X", "ts":74.895, "dur":1.119, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_1", "cat":"DMA", "ph":"X", "ts":76.171, "dur":0.911, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/_cluster_0", "cat":"DMA", "ph":"X", "ts":76.328, "dur":1.015, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/_cluster_1", "cat":"DMA", "ph":"X", "ts":83.593, "dur":1.171, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/_cluster_0", "cat":"DMA", "ph":"X", "ts":83.750, "dur":0.859, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/_cluster_0", "cat":"DMA", "ph":"X", "ts":84.921, "dur":0.625, "pid":0, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/_cluster_1", "cat":"DMA", "ph":"X", "ts":85.078, "dur":0.625, "pid":0, "tid":1},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/cluster_0", "cat":"DPU", "ph":"X", "ts":29.183, "dur":0.654, "pid":1, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/Duplicated_2/cluster_0", "cat":"DPU", "ph":"X", "ts":37.051, "dur":6.794, "pid":1, "tid":0},
// CHECK-NEXT: {"name":"relu1?t_Relu/cluster_0", "cat":"DPU", "ph":"X", "ts":45.680, "dur":10.095, "pid":1, "tid":0},
// CHECK-NEXT: {"name":"conv2/WithoutBiases?t_Convolution/cluster_0", "cat":"DPU", "ph":"X", "ts":56.393, "dur":10.192, "pid":1, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/cluster_0", "cat":"DPU", "ph":"X", "ts":67.196, "dur":4.357, "pid":1, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/tile_0/cluster_0", "cat":"SW", "ph":"X", "ts":17.526, "dur":6.848, "pid":1, "tid":1, "args":{"Active cycles:": "6765", "Stall cycles:": "1201"}},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/tile_1/cluster_0", "cat":"SW", "ph":"X", "ts":17.656, "dur":6.979, "pid":1, "tid":2, "args":{"Active cycles:": "6862", "Stall cycles:": "1276"}},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/tile_0/cluster_0", "cat":"SW", "ph":"X", "ts":77.864, "dur":4.921, "pid":1, "tid":1, "args":{"Active cycles:": "4639", "Stall cycles:": "973"}},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/tile_1/cluster_0", "cat":"SW", "ph":"X", "ts":78.125, "dur":4.401, "pid":1, "tid":2, "args":{"Active cycles:": "4593", "Stall cycles:": "1344"}},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/cluster_1", "cat":"DPU", "ph":"X", "ts":29.189, "dur":0.649, "pid":2, "tid":0},
// CHECK-NEXT: {"name":"conv1/WithoutBiases?t_Convolution/Duplicated_2/cluster_1", "cat":"DPU", "ph":"X", "ts":36.874, "dur":7.922, "pid":2, "tid":0},
// CHECK-NEXT: {"name":"relu1?t_Relu/cluster_1", "cat":"DPU", "ph":"X", "ts":45.832, "dur":6.895, "pid":2, "tid":0},
// CHECK-NEXT: {"name":"conv2/WithoutBiases?t_Convolution/cluster_1", "cat":"DPU", "ph":"X", "ts":55.896, "dur":10.761, "pid":2, "tid":0},
// CHECK-NEXT: {"name":"relu2?t_Relu/cluster_1", "cat":"DPU", "ph":"X", "ts":67.309, "dur":3.535, "pid":2, "tid":0},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/tile_0/cluster_1", "cat":"SW", "ph":"X", "ts":17.395, "dur":7.109, "pid":2, "tid":1, "args":{"Active cycles:": "6776", "Stall cycles:": "1092"}},
// CHECK-NEXT: {"name":"data?t_Parameter/converted_to_f16/tile_1/cluster_1", "cat":"SW", "ph":"X", "ts":17.786, "dur":6.979, "pid":2, "tid":2, "args":{"Active cycles:": "6860", "Stall cycles:": "1441"}},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/tile_1/cluster_1", "cat":"SW", "ph":"X", "ts":77.734, "dur":4.921, "pid":2, "tid":1, "args":{"Active cycles:": "4665", "Stall cycles:": "861"}},
// CHECK-NEXT: {"name":"relu2?t_Relu/converted_to_f32/tile_0/cluster_1", "cat":"SW", "ph":"X", "ts":77.994, "dur":4.921, "pid":2, "tid":2, "args":{"Active cycles:": "4615", "Stall cycles:": "1114"}},
// CHECK-NEXT: {"name":"data", "cat":"Layer", "ph":"X", "ts":0.000, "dur":27.134, "pid":3, "tid":0, "args":{"Layer type": "Parameter", "Shave time:": "27us 915ns", "DMA time:": "5us 126ns"}},
// CHECK-NEXT: {"name":"conv1/WithoutBiases", "cat":"Layer", "ph":"X", "ts":2.213, "dur":42.583, "pid":3, "tid":1, "args":{"Layer type": "Convolution", "DPU time:": "16us 19ns", "DMA time:": "14us 319ns"}},
// CHECK-NEXT: {"name":"conv2/WithoutBiases", "cat":"Layer", "ph":"X", "ts":37.031, "dur":29.626, "pid":3, "tid":0, "args":{"Layer type": "Convolution", "DPU time:": "20us 953ns", "DMA time:": "2us 500ns"}},
// CHECK-NEXT: {"name":"relu1", "cat":"Layer", "ph":"X", "ts":45.680, "dur":10.095, "pid":3, "tid":1, "args":{"Layer type": "Relu", "DPU time:": "16us 990ns"}},
// CHECK-NEXT: {"name":"relu2", "cat":"Layer", "ph":"X", "ts":67.196, "dur":18.507, "pid":3, "tid":0, "args":{"Layer type": "Relu", "DPU time:": "7us 892ns", "Shave time:": "19us 164ns", "DMA time:": "10us 724ns"}}
// CHECK-NEXT: ],
// CHECK-NEXT: "taskStatistics": {
// CHECK-NEXT: "total duration":85.703,
// CHECK-NEXT: "DMA duration":22.077,
// CHECK-NEXT: "DPU duration":33.790,
// CHECK-NEXT: "SW duration":12.551,
// CHECK-NEXT: "M2I duration":0.000,
// CHECK-NEXT: "DMA-DPU overlap":2.718,
// CHECK-NEXT: "DMA-SW overlap":0.000,
// CHECK-NEXT: "SW-DPU overlap":0.000,
// CHECK-NEXT: "all tasks union":65.700,
// CHECK-NEXT: "total idle":20.003,
// CHECK-NEXT: "SW duration without DPU overlap":12.551,
// CHECK-NEXT: "DMA duration without overlaps":19.359,
// CHECK-NEXT: "Sum of DMA task durations":32.669,
// CHECK-NEXT: "Sum of DPU task durations":61.854,
// CHECK-NEXT: "Sum of SW task durations":47.079,
// CHECK-NEXT: "Sum of M2I task durations":0.000
// CHECK-NEXT: },
// CHECK-NEXT: "workpoint": { "freq": 1300.0, "status": "OK" },
// CHECK-NEXT: "displayTimeUnit": "ns"
// CHECK-NEXT: }
