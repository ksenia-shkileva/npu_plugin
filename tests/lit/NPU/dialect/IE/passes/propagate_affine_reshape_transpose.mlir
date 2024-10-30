//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --propagate-affine-reshape --propagate-transpose --canonicalize %s | FileCheck %s
// REQUIRES: arch-NPU37XX || arch-NPU40XX

!qElemType = !quant.uniform<u8:f16, 0.11231384651333678:131>

// CHECK-LABEL: PropagateAffineReshapeAndTransposeSubgraph
func.func @PropagateAffineReshapeAndTransposeSubgraph(%arg0: tensor<1x768x512x1x!qElemType>) -> tensor<1x3072x512x1x!qElemType> {
    %cst = const.Declare tensor<3072x768x1x1x!qElemType> = dense<2.000000e+00> : tensor<3072x768x1x1xf16>, [#const.CastElemType<ui8>, #const.CastElemType<!qElemType>]
    %0 = IE.Convolution(%arg0, %cst) {
        dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]
    } : tensor<1x768x512x1x!qElemType>, tensor<3072x768x1x1x!qElemType> -> tensor<1x3072x512x1x!qElemType>
    %1 = IE.Transpose(%0) {order_value = affine_map<(d0, d1, d2, d3) -> (d2, d1, d0, d3)>} : tensor<1x3072x512x1x!qElemType> -> tensor<512x3072x1x1x!qElemType>
    %2 = IE.AffineReshape(%1) {dim_mapping = [[0, 1, 2], [3], [3], [3]], shape_value = [1, 1, 512, 3072]} : tensor<512x3072x1x1x!qElemType> -> tensor<1x1x512x3072x!qElemType>
    %3 = IE.AvgPool(%2) {exclude_pads, kernel_size = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], rounding_type = #IE.rounding_type<FLOOR>, strides = [1, 1]} : tensor<1x1x512x3072x!qElemType> -> tensor<1x1x512x3072xf16>
    %4 = IE.Gelu(%3) : tensor<1x1x512x3072xf16> -> tensor<1x1x512x3072xf16>
    %5 = IE.AvgPool(%4) {exclude_pads, kernel_size = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], rounding_type = #IE.rounding_type<FLOOR>, strides = [1, 1]} : tensor<1x1x512x3072xf16> -> tensor<1x1x512x3072x!qElemType>
    %6 = IE.AffineReshape(%5) {dim_mapping = [[0], [0], [0], [1, 2, 3]], shape_value = [512, 3072, 1, 1]} : tensor<1x1x512x3072x!qElemType> -> tensor<512x3072x1x1x!qElemType>
    %7 = IE.Transpose(%6) {order_value = affine_map<(d0, d1, d2, d3) -> (d2, d1, d0, d3)>} : tensor<512x3072x1x1x!qElemType> -> tensor<1x3072x512x1x!qElemType>
    return %7 : tensor<1x3072x512x1x!qElemType>

    // CHECK:       [[CST:%.+]] = const.Declare tensor<3072x768x1x1x!qElemType
    // CHECK:       [[CONV:%.+]] = IE.Convolution(%arg0, [[CST]])
    // CHECK-SAME:    -> tensor<1x3072x512x1x!qElemType>
    // CHECK:       [[AVG1:%.+]] = IE.AvgPool([[CONV]])
    // CHECK-SAME:       -> tensor<1x3072x512x1xf16>
    // CHECK:       [[GELU:%.+]] = IE.Gelu([[AVG1]])
    // CHECK-SAME:       -> tensor<1x3072x512x1xf16>
    // CHECK:       [[AVG2:%.+]] = IE.AvgPool([[GELU]])
    // CHECK-SAME:       -> tensor<1x3072x512x1x!qElemType>
    // CHECK:       return [[AVG2]] : tensor<1x3072x512x1x!qElemType>
}

// -----

#map = affine_map<(d0, d1, d2, d3) -> (d2, d1, d0, d3)>

// CHECK-LABEL: @PropagateAffineReshapeAndTransposeThroughAddWithSelectInput
// CHECK-SAME:     [[INPUT_0:%.+]]: tensor<1x1024x1024x1xf16>,
// CHECK-SAME:     [[INPUT_1:%.+]]: tensor<1x1x1024x1024xf16>
func.func @PropagateAffineReshapeAndTransposeThroughAddWithSelectInput(%arg0: tensor<1x1024x1024x1xf16>, %arg1: tensor<1x1x1024x1024xf16>) -> tensor<1x1024x1024x1xf16> {
    %0 = IE.Transpose(%arg0) {order_value = #map} : tensor<1x1024x1024x1xf16> -> tensor<1024x1024x1x1xf16>
    %1 = IE.AffineReshape(%0) {dim_mapping = [[0, 1, 2], [3], [3], [3]], shape_value = [1, 1, 1024, 1024]} : tensor<1024x1024x1x1xf16> -> tensor<1x1x1024x1024xf16>

    %cst_0 = const.Declare tensor<1x1x1x1xf16> = dense<-3.40282347E+38> : tensor<f32>, [#const.Reshape<[1, 1, 1, 1]>, #const.CastElemType<f16>]
    %cst_1 = const.Declare tensor<1x1x1024x1024xf16> = dense<3.0> : tensor<1x1x1024x1024xf32>, [#const.CastElemType<f16>]
    %2 = IE.Select(%arg1, %cst_0, %cst_1) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x1x1024x1024xf16>, tensor<1x1x1x1xf16>, tensor<1x1x1024x1024xf16> -> tensor<1x1x1024x1024xf16>

    %3 = IE.Add(%1, %2) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x1x1024x1024xf16>, tensor<1x1x1024x1024xf16> -> tensor<1x1x1024x1024xf16>

    %4 = IE.SoftMax(%3) {axisInd = 3 : i64} : tensor<1x1x1024x1024xf16> -> tensor<1x1x1024x1024xf16>

    %5 = IE.AffineReshape(%4) {dim_mapping = [[0], [0], [0], [1, 2, 3]], shape_value = [1024, 1024, 1, 1]} : tensor<1x1x1024x1024xf16> -> tensor<1024x1024x1x1xf16>

    %6 = IE.Transpose(%5) {order_value = #map} : tensor<1024x1024x1x1xf16> -> tensor<1x1024x1024x1xf16>

    return %6 : tensor<1x1024x1024x1xf16>

    // CHECK-DAG:       [[CST_0:%.+]] = const.Declare tensor<1x1x1x1xf16> = dense<-3.40282347E+38> : tensor<f32>, [#const.Reshape<[1, 1, 1, 1]>, #const.CastElemType<f16>]
    // CHECK-DAG:       [[CST_1:%.+]] = const.Declare tensor<1x1x1024x1024xf16> = dense<3.000000e+00> : tensor<1x1x1024x1024xf32>, [#const.CastElemType<f16>]
    // CHECK:           [[SELECT:%.+]] = IE.Select([[INPUT_1]], [[CST_0]], [[CST_1]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x1x1024x1024xf16>, tensor<1x1x1x1xf16>, tensor<1x1x1024x1024xf16> -> tensor<1x1x1024x1024xf16>
    // CHECK:           [[RESHAPE_0:%.+]] = IE.AffineReshape([[SELECT]])
    // CHECK-SAME{LITERAL}:     {dim_mapping = [[0], [0], [0], [1, 2, 3]], shape_value = [1024, 1024, 1, 1]} : tensor<1x1x1024x1024xf16> -> tensor<1024x1024x1x1xf16>
    // CHECK:           [[TRANSPOSE_0:%.+]] = IE.Transpose([[RESHAPE_0]]) {order_value = #map} : tensor<1024x1024x1x1xf16> -> tensor<1x1024x1024x1xf16>

    // CHECK:           [[ADD:%.+]] = IE.Add([[INPUT_0]], [[TRANSPOSE_0]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x1024x1024x1xf16>, tensor<1x1024x1024x1xf16> -> tensor<1x1024x1024x1xf16>

    // CHECK:           [[SOFTMAX:%.+]] = IE.SoftMax([[ADD]]) {axisInd = 1 : i64} : tensor<1x1024x1024x1xf16> -> tensor<1x1024x1024x1xf16>

    // CHECK:           return [[SOFTMAX]] : tensor<1x1024x1024x1xf16>
}

// -----

#map = affine_map<(d0, d1, d2, d3) -> (d2, d1, d0, d3)>

// CHECK-LABEL: @PropagateAffineReshapeAndTransposeThroughAddWithConvertInput
// CHECK-SAME:     [[INPUT_0:%.+]]: tensor<1x1024x1024x1xf16>,
// CHECK-SAME:     [[INPUT_1:%.+]]: tensor<1x1x1024x1024xf32>
func.func @PropagateAffineReshapeAndTransposeThroughAddWithConvertInput(%arg0: tensor<1x1024x1024x1xf16>, %arg1: tensor<1x1x1024x1024xf32>) -> tensor<1x1024x1024x1xf16> {
    %0 = IE.Transpose(%arg0) {order_value = #map} : tensor<1x1024x1024x1xf16> -> tensor<1024x1024x1x1xf16>
    %1 = IE.AffineReshape(%0) {dim_mapping = [[0, 1, 2], [3], [3], [3]], shape_value = [1, 1, 1024, 1024]} : tensor<1024x1024x1x1xf16> -> tensor<1x1x1024x1024xf16>

    %2 = IE.Convert(%arg1) {dstElemType = f16} : tensor<1x1x1024x1024xf32> -> tensor<1x1x1024x1024xf16>

    %3 = IE.Add(%1, %2) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x1x1024x1024xf16>, tensor<1x1x1024x1024xf16> -> tensor<1x1x1024x1024xf16>

    %4 = IE.SoftMax(%3) {axisInd = 3 : i64} : tensor<1x1x1024x1024xf16> -> tensor<1x1x1024x1024xf16>

    %5 = IE.AffineReshape(%4) {dim_mapping = [[0], [0], [0], [1, 2, 3]], shape_value = [1024, 1024, 1, 1]} : tensor<1x1x1024x1024xf16> -> tensor<1024x1024x1x1xf16>

    %6 = IE.Transpose(%5) {order_value = #map} : tensor<1024x1024x1x1xf16> -> tensor<1x1024x1024x1xf16>

    return %6 : tensor<1x1024x1024x1xf16>

    // CHECK:           [[CONVERT:%.+]] = IE.Convert([[INPUT_1]]) {dstElemType = f16} : tensor<1x1x1024x1024xf32> -> tensor<1x1x1024x1024xf16>
    // CHECK:           [[RESHAPE_0:%.+]] = IE.AffineReshape([[CONVERT]])
    // CHECK-SAME{LITERAL}:     {dim_mapping = [[0], [0], [0], [1, 2, 3]], shape_value = [1024, 1024, 1, 1]} : tensor<1x1x1024x1024xf16> -> tensor<1024x1024x1x1xf16>
    // CHECK:           [[TRANSPOSE_0:%.+]] = IE.Transpose([[RESHAPE_0]]) {order_value = #map} : tensor<1024x1024x1x1xf16> -> tensor<1x1024x1024x1xf16>

    // CHECK:           [[ADD:%.+]] = IE.Add([[INPUT_0]], [[TRANSPOSE_0]]) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} : tensor<1x1024x1024x1xf16>, tensor<1x1024x1024x1xf16> -> tensor<1x1024x1024x1xf16>

    // CHECK:           [[SOFTMAX:%.+]] = IE.SoftMax([[ADD]]) {axisInd = 1 : i64} : tensor<1x1024x1024x1xf16> -> tensor<1x1024x1024x1xf16>

    // CHECK:           return [[SOFTMAX]] : tensor<1x1024x1024x1xf16>
}

// -----

!qElemType = !quant.uniform<i4:f16, 1.3385416666666667>

// CHECK-LABEL: @PropagateAffineReshapeAndTransposeThroughAddWithSymmetricalInput
// CHECK-SAME:     [[INPUT_0:%.+]]: tensor<1x128x1024x1xf16>,
// CHECK-SAME:     [[INPUT_1:%.+]]: tensor<1x128x1024x1xf16>
func.func @PropagateAffineReshapeAndTransposeThroughAddWithSymmetricalInput(%arg0: tensor<1x128x1024x1xf16>, %arg1: tensor<1x128x1024x1xf16>) -> tensor<1x1x1024x3584xf16> {
    %weights0 = const.Declare tensor<3584x128x1x1x!qElemType> = dense<1.000000e+00> :
        tensor<3584x128x1x1xf16>, [#const.CastElemType<si4>, #const.CastElemType<!qElemType>]
    %weights1 = const.Declare tensor<3584x128x1x1x!qElemType> = dense<2.000000e+00> :
        tensor<3584x128x1x1xf16>, [#const.CastElemType<si4>, #const.CastElemType<!qElemType>]

    %0 = IE.Convolution(%arg0, %weights0) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x128x1024x1xf16>, tensor<3584x128x1x1x!qElemType> -> tensor<1x3584x1024x1xf16>
    %1 = IE.Transpose(%0) {order_value = affine_map<(d0, d1, d2, d3) -> (d2, d1, d0, d3)>} : tensor<1x3584x1024x1xf16> -> tensor<1024x3584x1x1xf16>
    %2 = IE.AffineReshape(%1) {dim_mapping = [[0, 1, 2], [3], [3], [3]], shape_value = [1, 1, 1024, 3584]} : tensor<1024x3584x1x1xf16> -> tensor<1x1x1024x3584xf16>

    %3 = IE.Convolution(%arg1, %weights1) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x128x1024x1xf16>, tensor<3584x128x1x1x!qElemType> -> tensor<1x3584x1024x1xf16>
    %4 = IE.Transpose(%3) {order_value = affine_map<(d0, d1, d2, d3) -> (d2, d1, d0, d3)>} : tensor<1x3584x1024x1xf16> -> tensor<1024x3584x1x1xf16>
    %5 = IE.AffineReshape(%4) {dim_mapping = [[0, 1, 2], [3], [3], [3]], shape_value = [1, 1, 1024, 3584]} : tensor<1024x3584x1x1xf16> -> tensor<1x1x1024x3584xf16>

    %6 = IE.Add(%2, %5) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x1x1024x3584xf16>, tensor<1x1x1024x3584xf16> -> tensor<1x1x1024x3584xf16>

    return %6 : tensor<1x1x1024x3584xf16>

    // CHECK:           [[WEIGHTS_0:%.+]] = const.Declare tensor<3584x128x1x1x!qElemType> = dense<1.000000e+00> : tensor<3584x128x1x1xf16>, [#const.CastElemType<si4>, #const.CastElemType<!qElemType>]
    // CHECK:           [[WEIGHTS_1:%.+]] = const.Declare tensor<3584x128x1x1x!qElemType> = dense<2.000000e+00> : tensor<3584x128x1x1xf16>, [#const.CastElemType<si4>, #const.CastElemType<!qElemType>]

    // CHECK:           [[CONV_0:%.+]] = IE.Convolution([[INPUT_0]], [[WEIGHTS_0]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x128x1024x1xf16>, tensor<3584x128x1x1x!qElemType> -> tensor<1x3584x1024x1xf16>
    // CHECK:           [[CONV_1:%.+]] = IE.Convolution([[INPUT_1]], [[WEIGHTS_1]]) {dilations = [1, 1], pads_begin = [0, 0], pads_end = [0, 0], strides = [1, 1]} : tensor<1x128x1024x1xf16>, tensor<3584x128x1x1x!qElemType> -> tensor<1x3584x1024x1xf16>

    // CHECK:           [[ADD:%.+]] = IE.Add([[CONV_0]], [[CONV_1]]) {auto_broadcast = #IE.auto_broadcast_type<NONE_OR_EXPLICIT>} : tensor<1x3584x1024x1xf16>, tensor<1x3584x1024x1xf16> -> tensor<1x3584x1024x1xf16>

    // CHECK:           [[TRANSPOSE:%.+]] = IE.Transpose([[ADD]]) {order_value = #map} : tensor<1x3584x1024x1xf16> -> tensor<1024x3584x1x1xf16>
    // CHECK:           [[RESHAPE:%.+]] = IE.AffineReshape([[TRANSPOSE]])
    // CHECK-SAME{LITERAL}:     {dim_mapping = [[0, 1, 2], [3], [3], [3]], shape_value = [1, 1, 1024, 3584]} : tensor<1024x3584x1x1xf16> -> tensor<1x1x1024x3584xf16>

    // CHECK:           return [[RESHAPE]] : tensor<1x1x1024x3584xf16>
}
