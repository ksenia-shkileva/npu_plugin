//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --decompose-mvn %s | FileCheck %s
// REQUIRES: arch-NPU37XX || arch-NPU40XX

// CHECK-LABEL: func.func @NotDecomposeMVN
// CHECK-SAME:        [[INPUT:%arg[0-9]]]: tensor<1x3x16x32xf16>
func.func @NotDecomposeMVN(%arg0: tensor<1x3x16x32xf16>) -> (tensor<1x3x16x32xf16>) {
      %0 = VPU.MVN(%arg0) {across_channels = false, eps = 6.0892105102539063E-4 : f64, normalize_variance = true} : tensor<1x3x16x32xf16> -> tensor<1x3x16x32xf16>
      return %0 : tensor<1x3x16x32xf16>

    // CHECK:            [[VAL0:%.+]] = VPU.MVN([[INPUT]])
    // CHECK:            return [[VAL0]]
}

// -----

// CHECK-LABEL: func.func @NoTilingDecomposeMVN
// CHECK-SAME:        [[INPUT:%arg[0-9]]]: tensor<1x1x1x515971xf16>
func.func @NoTilingDecomposeMVN(%arg0: tensor<1x1x1x515971xf16>) -> (tensor<1x1x1x515971xf16>) {
      %0 = VPU.MVN(%arg0) {across_channels = false, eps = 6.0892105102539063E-4 : f64, normalize_variance = true} : tensor<1x1x1x515971xf16> -> tensor<1x1x1x515971xf16>
      return %0 : tensor<1x1x1x515971xf16>

    // CHECK:             [[RESHAPE:%.+]] = VPU.AffineReshape([[INPUT]])
    // CHECK-SAME{LITERAL}:   {dim_mapping = [[0], [1], [2], [3]], shape_value = [1, 1, 515971, 1]} : tensor<1x1x1x515971xf16> -> tensor<1x1x515971x1xf16>
    // CHECK:            [[VAL0:%.+]] = VPU.MVN1SumOp([[RESHAPE]])
    // CHECK-SAME:          tensor<1x1x515971x1xf16> -> tensor<1x1x1x2xf32, {order = #NHWC}>
    // CHECK:            [[VAL1:%.+]] = VPU.MVN1MeanVar([[VAL0]])
    // CHECK:            [[VAL2:%.+]] = VPU.MVN1Normalize(%arg0, [[VAL1]])
    // CHECK:            return [[VAL2]]
}
