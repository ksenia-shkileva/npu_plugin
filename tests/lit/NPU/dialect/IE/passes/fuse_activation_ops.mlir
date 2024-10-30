//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch% compilation-mode=DefaultHW" --fuse-activation-ops="enable-fuse-clamp=false" %s | FileCheck %s
// REQUIRES: arch-NPU37XX || arch-NPU40XX

func.func @Conv2dWithReluTest(%arg0: tensor<1x16x4x4xf16>) -> tensor<1x16x3x3xf16> {
    %filters = const.Declare tensor<16x16x2x2xf16> = dense<1.0> : tensor<16x16x2x2xf16>
    %0 = IE.Convolution(%arg0, %filters)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<1x16x4x4xf16>, tensor<16x16x2x2xf16> -> tensor<1x16x3x3xf16>

    %1 = IE.ReLU(%0) :
        tensor<1x16x3x3xf16> -> tensor<1x16x3x3xf16>

    return %1 : tensor<1x16x3x3xf16>

    // CHECK:       IE.Convolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.ReLU", attrs = {}>
    // CHECK-SAME:     strides = [1, 1]
    // CHECK-NOT:   IE.ReLU
}

// -----

func.func @DepthWiseConv2dWithReluTest(%arg0: tensor<1x16x4x4xf16>) -> tensor<1x16x3x3xf16> {
    %filters = const.Declare tensor<16x1x2x2xf16> = dense<1.0> : tensor<16x1x1x2x2xf16>, [#const.Reshape<[16, 1, 2, 2]>]
    %0 = IE.GroupConvolution(%arg0, %filters)
        {
            dilations = [1, 1],
            groups = 16,
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0]
        } :
        tensor<1x16x4x4xf16>, tensor<16x1x2x2xf16> -> tensor<1x16x3x3xf16>

    %1 = IE.ReLU(%0) :
        tensor<1x16x3x3xf16> -> tensor<1x16x3x3xf16>

    return %1 : tensor<1x16x3x3xf16>

    // CHECK:       IE.GroupConvolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     groups = 16
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.ReLU", attrs = {}>
    // CHECK-SAME:     strides = [1, 1]
    // CHECK-NOT:   IE.ReLU
}

// -----

func.func @Conv2dWithClampTest(%arg0: tensor<1x16x4x4xf16>) -> tensor<1x16x3x3xf16> {
    %filters = const.Declare tensor<16x16x2x2xf16> = dense<1.0> : tensor<16x16x2x2xf16>
    %0 = IE.Convolution(%arg0, %filters)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<1x16x4x4xf16>, tensor<16x16x2x2xf16> -> tensor<1x16x3x3xf16>

    %1 = IE.Clamp(%0)
        {
            max = 6.000000e+00,
            min = 0.000000e+00
        } :
        tensor<1x16x3x3xf16> -> tensor<1x16x3x3xf16>

    return %1 : tensor<1x16x3x3xf16>

    // CHECK:       IE.Convolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.000000e+00 : f64, min = 0.000000e+00 : f64}>
    // CHECK-SAME:     strides = [1, 1]
    // CHECK-NOT:   IE.Clamp
}

// -----

!qElemType = !quant.uniform<u8:f16, 1.000000e+00:127>
!qElemType1 = !quant.uniform<u8<0:254>:f16, 1.0>
!qElemType2 = !quant.uniform<u8:f16, 0.15748031466614967:128>

func.func @QuantizedConv2dWithClampTest(%arg0: tensor<1x16x20x20x!qElemType>) -> tensor<1x32x20x20x!qElemType2> {
    %filters = const.Declare tensor<32x16x1x1x!qElemType1> = dense<1.0> : tensor<32x16x1x1xf32>,
                    [#const.CastElemType<f16>, #const.CastElemType<ui8>, #const.CastElemType<!qElemType1>]

    %0 = IE.Convolution(%arg0, %filters)
        {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1]
        } :
        tensor<1x16x20x20x!qElemType>, tensor<32x16x1x1x!qElemType1> -> tensor<1x32x20x20x!qElemType2>

    %1 = IE.Clamp(%0)
        {
            max = 5.000000e+00 : f64,
            min = -5.000000e+00 : f64
        } :
        tensor<1x32x20x20x!qElemType2> -> tensor<1x32x20x20x!qElemType2>

    return %1 : tensor<1x32x20x20x!qElemType2>

    // CHECK:       IE.Convolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 5.000000e+00 : f64, min = -5.000000e+00 : f64}>
    // CHECK-SAME:     strides = [1, 1]
    // CHECK-NOT:   IE.Clamp
}

// -----

func.func @AddWithReLUTest() -> tensor<1x16x4x4xf16> {
    %0 = const.Declare tensor<1x16x4x4xf16> = dense<6.0> : tensor<1x16x4x4xf16>
    %1 = const.Declare tensor<1x16x4x4xf16> = dense<-7.0> : tensor<1x16x4x4xf16>
    %sum = IE.Add(%0, %1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } : tensor<1x16x4x4xf16>, tensor<1x16x4x4xf16> -> tensor<1x16x4x4xf16>
    %relu = IE.ReLU(%sum) : tensor<1x16x4x4xf16> -> tensor<1x16x4x4xf16>

    return %relu : tensor<1x16x4x4xf16>

    // CHECK-DAG:       %[[RIGHT:.*]] = const.Declare tensor<1x16x4x4xf16> = dense<-7.000000e+00> : tensor<1x16x4x4xf16>
    // CHECK-DAG:       %[[LEFT:.*]] = const.Declare tensor<1x16x4x4xf16> = dense<6.000000e+00> : tensor<1x16x4x4xf16>
    // CHECK:       %[[SUM:.*]] = IE.Add(%[[LEFT]], %[[RIGHT]])
    // CHECK-SAME:     auto_broadcast = #IE.auto_broadcast_type<NUMPY>
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.ReLU", attrs = {}>
    // CHECK-NOT:   IE.ReLU
}

// -----

func.func @AddWithLeakyReluTest() -> tensor<1x16x4x4xf16> {
    %0 = const.Declare tensor<1x16x4x4xf16> = dense<6.0> : tensor<1x16x4x4xf16>
    %1 = const.Declare tensor<1x16x4x4xf16> = dense<-7.0> : tensor<1x16x4x4xf16>
    %sum = IE.Add(%0, %1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } : tensor<1x16x4x4xf16>, tensor<1x16x4x4xf16> -> tensor<1x16x4x4xf16>
    %leakyRelu = IE.LeakyRelu(%sum) {
            negative_slope = 0.100000e+00
        } : tensor<1x16x4x4xf16> -> tensor<1x16x4x4xf16>

    return %leakyRelu : tensor<1x16x4x4xf16>

    // CHECK-DAG:       %[[RIGHT:.*]] = const.Declare tensor<1x16x4x4xf16> = dense<-7.000000e+00> : tensor<1x16x4x4xf16>
    // CHECK-DAG:       %[[LEFT:.*]] = const.Declare tensor<1x16x4x4xf16> = dense<6.000000e+00> : tensor<1x16x4x4xf16>
    // CHECK:       %[[SUM:.*]] = IE.Add(%[[LEFT]], %[[RIGHT]])
    // CHECK:   IE.LeakyRelu
}

// -----

func.func @ShouldNotFuseScaleShiftTest(%arg0: tensor<1x16x4x4xf16>) -> tensor<1x16x3x3xf16> {
    %filters = const.Declare tensor<16x16x2x2xf16> = dense<1.0> : tensor<16x16x2x2xf16>
    %0 = IE.Convolution(%arg0, %filters)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<1x16x4x4xf16>, tensor<16x16x2x2xf16> -> tensor<1x16x3x3xf16>

    %bias = const.Declare tensor<1x16x1x1xf32> = dense<3.0> : tensor<1x16x1x1xf32>
    %1 = IE.ScaleShift(%0, %bias)
        {operandSegmentSizes = array<i32: 1, 0, 1>} :
        tensor<1x16x3x3xf16>, tensor<1x16x1x1xf32> -> tensor<1x16x3x3xf16>

    return %1 : tensor<1x16x3x3xf16>

    // CHECK:   IE.Convolution
    // CHECK:   IE.ScaleShift
}

// -----

func.func @Conv2dWithLeakyReluTest(%arg0: tensor<1x16x4x4xf16>) -> tensor<1x16x3x3xf16> {
    %filters = const.Declare tensor<16x16x2x2xf16> = dense<1.0> : tensor<16x16x2x2xf16>
    %0 = IE.Convolution(%arg0, %filters)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<1x16x4x4xf16>, tensor<16x16x2x2xf16> -> tensor<1x16x3x3xf16>

    %1 = IE.LeakyRelu(%0) {negative_slope = 1.000000e-01 : f64} : tensor<1x16x3x3xf16> -> tensor<1x16x3x3xf16>

    return %1 : tensor<1x16x3x3xf16>

    // CHECK:       IE.Convolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 1.000000e-01 : f64}>
    // CHECK-SAME:     strides = [1, 1]
    // CHECK-NOT:   IE.LeakyRelu
}

// -----

func.func @Conv2dWithLeakyRelu15Test(%arg0: tensor<1x16x4x4xf16>) -> tensor<1x16x3x3xf16> {
    %filters = const.Declare tensor<16x16x2x2xf16> = dense<1.0> : tensor<16x16x2x2xf16>
    %0 = IE.Convolution(%arg0, %filters)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<1x16x4x4xf16>, tensor<16x16x2x2xf16> -> tensor<1x16x3x3xf16>

    %1 = IE.LeakyRelu(%0) {negative_slope = 1.500000e-01 : f64} : tensor<1x16x3x3xf16> -> tensor<1x16x3x3xf16>

    return %1 : tensor<1x16x3x3xf16>

    // CHECK:       IE.Convolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 1.500000e-01 : f64}>
    // CHECK-SAME:     strides = [1, 1]
    // CHECK-NOT:   IE.LeakyRelu
}

// -----

func.func @TransposedConv2dWithLeakyReluTest(%arg0: tensor<1x32x64x100xf16>) -> tensor<1x16x128x101xf16> {
    %filters = const.Declare tensor<16x32x3x2xf16> = dense<1.0> : tensor<16x32x3x2xf16>
    %0 = IE.TransposedConvolution(%arg0, %filters)
        {
            dilations = [1, 1],
            operandSegmentSizes = array<i32: 1, 1, 0, 0>,
            output_padding = [1, 0],
            pads_begin = [1, 0],
            pads_end = [1, 0],
            strides = [2, 1]
        } :
        tensor<1x32x64x100xf16>, tensor<16x32x3x2xf16> -> tensor<1x16x128x101xf16>

    %1 = IE.LeakyRelu(%0) {negative_slope = 1.500000e-01 : f64} : tensor<1x16x128x101xf16> -> tensor<1x16x128x101xf16>

    return %1 : tensor<1x16x128x101xf16>

    // CHECK:       IE.TransposedConvolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     operandSegmentSizes = array<i32: 1, 1, 0, 0>
    // CHECK-SAME:     output_padding = [1, 0]
    // CHECK-SAME:     pads_begin = [1, 0]
    // CHECK-SAME:     pads_end = [1, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 1.500000e-01 : f64}>
    // CHECK-SAME:     strides = [2, 1]
    // CHECK-NOT:   IE.LeakyRelu
}

// -----

func.func @TransposedConv2dWithLeakyReluNotFuseTest(%arg0: tensor<1x32x64x100xf16>, %arg1: tensor<16x32x3x2xf16>) -> tensor<1x16x128x101xf16> {
    %0 = IE.TransposedConvolution(%arg0, %arg1)
        {
            dilations = [1, 1],
            operandSegmentSizes = array<i32: 1, 1, 0, 0>,
            output_padding = [1, 0],
            pads_begin = [1, 0],
            pads_end = [1, 0],
            strides = [2, 1]
        } :
        tensor<1x32x64x100xf16>, tensor<16x32x3x2xf16> -> tensor<1x16x128x101xf16>

    %1 = IE.LeakyRelu(%0) {negative_slope = 1.500000e-01 : f64} : tensor<1x16x128x101xf16> -> tensor<1x16x128x101xf16>

    return %1 : tensor<1x16x128x101xf16>

    // CHECK:       IE.TransposedConvolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     operandSegmentSizes = array<i32: 1, 1, 0, 0>
    // CHECK-SAME:     output_padding = [1, 0]
    // CHECK-SAME:     pads_begin = [1, 0]
    // CHECK-SAME:     pads_end = [1, 0]
    // CHECK-SAME:     strides = [2, 1]
    // CHECK:     IE.LeakyRelu
}

// -----

!qElemType = !quant.uniform<u8:f16, 0.034064797794117647:55>
 
func.func @ConvWithLeakyReluFuseQuantType(
    %arg0: tensor<128x128x1x1x!qElemType>,
    %arg1: tensor<512x128x1x1x!qElemType>
) -> tensor<128x512x1x1x!qElemType> {
    %0 = IE.Convolution(%arg0, %arg1)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<128x128x1x1x!qElemType>, tensor<512x128x1x1x!qElemType> -> tensor<128x512x1x1x!qElemType>
 
    %1 = IE.LeakyRelu(%0) {negative_slope = 0.300048828125 : f64} : tensor<128x512x1x1x!qElemType> -> tensor<128x512x1x1x!qElemType>
 
    return %1 : tensor<128x512x1x1x!qElemType>

    // CHECK:       IE.Convolution
    // CHECK-SAME:     dilations = [1, 1]
    // CHECK-SAME:     pads_begin = [0, 0]
    // CHECK-SAME:     pads_end = [0, 0]
    // CHECK-SAME:     post_op = #IE.PostOp<name = "IE.LeakyRelu" 
    // CHECK-SAME:     attrs = {negative_slope = 0.300048828125 : f64}>
    // CHECK-SAME:     strides = [1, 1]
 
}

// -----

!qElemType = !quant.uniform<u8:f16, 0.034064797794117647:55>
!qElemType1 = !quant.uniform<u8:f16, 0.054064797794117647:55>
 
func.func @ConvWithLeakyReluFuseDiffTypes(
    %arg0: tensor<128x128x1x1x!qElemType>,
    %arg1: tensor<512x128x1x1x!qElemType>
) -> tensor<128x512x1x1x!qElemType1> {
    %0 = IE.Convolution(%arg0, %arg1)
        {
            strides = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            dilations = [1, 1]
        } :
        tensor<128x128x1x1x!qElemType>, tensor<512x128x1x1x!qElemType> -> tensor<128x512x1x1x!qElemType>
 
    %1 = IE.LeakyRelu(%0) {negative_slope = 0.300048828125 : f64} : tensor<128x512x1x1x!qElemType> -> tensor<128x512x1x1x!qElemType1>
 
    return %1 : tensor<128x512x1x1x!qElemType1>

    // CHECK:       IE.Convolution
    // CHECK-SAME:    dilations = [1, 1]
    // CHECK-SAME:    pads_begin = [0, 0]
    // CHECK-SAME:    pads_end = [0, 0]
    // CHECK-SAME:    post_op = #IE.PostOp<name = "IE.LeakyRelu" 
    // CHECK-SAME:    attrs = {negative_slope = 0.300048828125 : f64}>
    // CHECK-SAME:    strides = [1, 1]
    // CHECK-SAME:    tensor<128x128x1x1x!qElemType>, tensor<512x128x1x1x!qElemType> -> tensor<128x512x1x1x!qElemType1>
 
}
