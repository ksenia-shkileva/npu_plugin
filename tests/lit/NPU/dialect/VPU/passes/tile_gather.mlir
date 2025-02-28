
//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --tile-gather %s | FileCheck %s
// REQUIRES: arch-NPU40XX


// -----

// CHECK-LABEL: @TileGatherElement
// CHECK-SAME: ([[ARG0:%.*]]: tensor<12x4096xf16>, [[ARG1:%.*]]:  tensor<1x1xsi32>)

func.func @TileGatherElement(%arg0: tensor<12x4096xf16>,%arg1: tensor<1x1xsi32>) -> tensor<1x1x4096xf16> {
    %0 =  VPU.Gather(%arg0, %arg1) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x4096xf16>, tensor<1x1xsi32> -> tensor<1x1x4096xf16>
    return %0 :  tensor<1x1x4096xf16>

    // CHECK:       [[TILE0:%.*]] = VPU.Slice [[ARG0]] [0, 0] [12, 2048] : tensor<12x4096xf16> to tensor<12x2048xf16>
    // CHECK:       [[GATHER0:%.*]] = VPU.Gather([[TILE0]], [[ARG1]]) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x2048xf16>, tensor<1x1xsi32> -> tensor<1x1x2048xf16>
    // CHECK:       [[TILE1:%.*]] = VPU.Slice [[ARG0]] [0, 2048] [12, 2048] : tensor<12x4096xf16> to tensor<12x2048xf16>
    // CHECK:       [[GATHER1:%.*]]  = VPU.Gather([[TILE1]], [[ARG1]]) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x2048xf16>, tensor<1x1xsi32> -> tensor<1x1x2048xf16>
    // CHECK:       [[CONCAT:%.*]]  = VPU.Concat([[GATHER0]], [[GATHER1]])
    // CHECK-SAME{LITERAL}              {static_offsets = [[0, 0, 0], [0, 0, 2048]]} : tensor<1x1x2048xf16>, tensor<1x1x2048xf16> -> tensor<1x1x4096xf16>
    // CHECK:       return      [[CONCAT]] : tensor<1x1x4096xf16>
}

// -----

// CHECK-LABEL: @TileGatherIndices

func.func @TileGatherIndices(%arg0: tensor<12x1xf16>,%arg1: tensor<1x100000xsi32>) -> tensor<1x100000x1xf16> {
    %0 =  VPU.Gather(%arg0, %arg1) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x1xf16>, tensor<1x100000xsi32> -> tensor<1x100000x1xf16>
    return %0 :  tensor<1x100000x1xf16>

    // CHECK:       [[TILE0:%.*]] = VPU.Slice {{[^:]+}} [0, 0] [1, 50000] : tensor<1x100000xsi32> to tensor<1x50000xsi32>
    // CHECK:       [[GATHER0:%.*]] = VPU.Gather({{[^:]+}}, [[TILE0]]) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x1xf16>, tensor<1x50000xsi32> -> tensor<1x50000x1xf16>
    // CHECK:       [[TILE1:%.*]] = VPU.Slice {{[^:]+}} [0, 50000] [1, 50000] : tensor<1x100000xsi32> to tensor<1x50000xsi32>
    // CHECK:       [[GATHER1:%.*]] = VPU.Gather({{[^:]+}}, [[TILE1]]) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x1xf16>, tensor<1x50000xsi32> -> tensor<1x50000x1xf16>
    // CHECK:       [[CONCAT:%.*]] = VPU.Concat([[GATHER0]], [[GATHER1]])
    // CHECK-SAME{LITERAL}              {static_offsets = [[0, 0, 0], [0, 50000, 0]]} : tensor<1x50000x1xf16>, tensor<1x50000x1xf16> -> tensor<1x100000x1xf16>
    // CHECK:       return [[CONCAT]] : tensor<1x100000x1xf16>
}

// -----

// CHECK-LABEL: @NotTileGatherForSmallSize
// CHECK-SAME: ([[ARG0:%.*]]: tensor<12x2048xf16>, [[ARG1:%.*]]:  tensor<1x1xsi32>)

func.func @NotTileGatherForSmallSize(%arg0: tensor<12x2048xf16>,%arg1: tensor<1x1xsi32>) -> tensor<1x1x2048xf16> {
    %0 =  VPU.Gather(%arg0, %arg1) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x2048xf16>, tensor<1x1xsi32> -> tensor<1x1x2048xf16>
    return %0 :  tensor<1x1x2048xf16>

    // CHECK:       [[GATHER:%.*]] = VPU.Gather([[ARG0]], [[ARG1]]) {axis_value = 0 : i64, batch_dims = 0 : i64} : tensor<12x2048xf16>, tensor<1x1xsi32> -> tensor<1x1x2048xf16>
    // CHECK:       return      [[GATHER]] : tensor<1x1x2048xf16>
}

// -----

// CHECK-LABEL: @NotTileGatherForCouldNotConverToGatherDMA
// CHECK-SAME: ([[ARG0:%.*]]: tensor<3x12x4096xf16>, [[ARG1:%.*]]:  tensor<1x1xsi32>)

func.func @NotTileGatherForCouldNotConverToGatherDMA(%arg0: tensor<3x12x4096xf16>,%arg1: tensor<1x1xsi32>) -> tensor<3x1x1x4096xf16> {
    %0 =  VPU.Gather(%arg0, %arg1) {axis_value = 1 : i64, batch_dims = 0 : i64} : tensor<3x12x4096xf16>, tensor<1x1xsi32> -> tensor<3x1x1x4096xf16>
    return %0 :  tensor<3x1x1x4096xf16>

    // CHECK:       [[GATHER:%.*]] = VPU.Gather([[ARG0]], [[ARG1]]) {axis_value = 1 : i64, batch_dims = 0 : i64} : tensor<3x12x4096xf16>, tensor<1x1xsi32> -> tensor<3x1x1x4096xf16>
    // CHECK:       return      [[GATHER]] : tensor<3x1x1x4096xf16>
}
