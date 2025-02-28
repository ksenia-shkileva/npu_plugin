//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch% compilation-mode=DefaultHW" --convert-IE-to-VPU-NCE %s | FileCheck %s
// REQUIRES: arch-NPU37XX || arch-NPU40XX

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @DepthConvToNCE
func.func @DepthConvToNCE(%arg0: tensor<1x16x40x80xf16, {order = #NHWC}>) -> tensor<1x16x37x73xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<16x1x4x8xf16, {order = #NHWC}> =
        dense<1.000000e+00> : tensor<16x1x4x8xf16>, [#const.Reorder<#NHWC>]

    %0 = IE.GroupConvolution(%arg0, %weights) {
            dilations = [1, 1],
            groups = 16,
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 0.1}>
        } : tensor<1x16x40x80xf16, {order = #NHWC}>, tensor<16x1x4x8xf16, {order = #NHWC}>
            -> tensor<1x16x37x73xf16, {order = #NHWC}>

    return %0 : tensor<1x16x37x73xf16, {order = #NHWC}>

    // CHECK-DAG:       [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32>
    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<16x1x4x8xf16, {order = #NHWC}>

    // CHECK:       [[OUT:%.+]] = VPU.NCE.DepthConvolution(%arg0, [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:      pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <LPRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1638 : i64, lrelu_shift = 14 : i64>
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      -> tensor<1x16x37x73xf16, {order = #NHWC}>

    // CHECK:       return [[OUT]] : tensor<1x16x37x73xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @EltwiseAddWithReluRewriter
func.func @EltwiseAddWithReluRewriter(%arg0: tensor<1x64x28x28xf16, {order = #NHWC}>, %arg1: tensor<1x64x28x28xf16, {order = #NHWC}>)
        -> tensor<1x64x28x28xf16, {order = #NHWC}> {
    %0 = IE.Add(%arg0, %arg1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY>, post_op = #IE.PostOp<name = "IE.ReLU", attrs = {}> } :
        tensor<1x64x28x28xf16, {order = #NHWC}>, tensor<1x64x28x28xf16, {order = #NHWC}>
        -> tensor<1x64x28x28xf16, {order = #NHWC}>

    return %0 : tensor<1x64x28x28xf16, {order = #NHWC}>

    // CHECK:       [[OUT:%.+]] = VPU.NCE.Eltwise(%arg0, %arg1)
    // CHECK-SAME:      op_type = #VPU.eltwise_type<ADD>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <ADD>, clamp_low = 0 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, quant_scale = [1.000000e+00]>}
    // CHECK-SAME:      -> tensor<1x64x28x28xf16, {order = #NHWC}>

    // CHECK:       return [[OUT]] : tensor<1x64x28x28xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @MaxPoolToNCE
func.func @MaxPoolToNCE(%arg0: tensor<1x16x1x4xf16, {order = #NHWC}>) -> tensor<1x16x1x4xf16, {order = #NHWC}> {
    %0 = IE.MaxPool(%arg0) {
            kernel_size = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            rounding_type = #IE.rounding_type<FLOOR>,
            post_op = #IE.PostOp<name = "IE.Clamp", attrs = {max = 6.0, min = 0.0}>
        } : tensor<1x16x1x4xf16, {order = #NHWC}> -> tensor<1x16x1x4xf16, {order = #NHWC}>

    return %0 : tensor<1x16x1x4xf16, {order = #NHWC}>

    // CHECK:       [[OUT:%.+]] = VPU.NCE.MaxPool(%arg0)
    // CHECK-SAME:      pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = 0 : i64, clamp_high = 393216 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64>
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      -> tensor<1x16x1x4xf16, {order = #NHWC}>

    // CHECK:       return [[OUT]] : tensor<1x16x1x4xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @AveragePoolToNCE
func.func @AveragePoolToNCE(%arg0: tensor<1x64x28x28xf16, {order = #NHWC}>)
        -> tensor<1x64x14x14xf16, {order = #NHWC}> {
    %0 = IE.AvgPool(%arg0) {
            kernel_size = [2, 2],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            rounding_type = #IE.rounding_type<FLOOR>,
            strides = [2, 2]
         } : tensor<1x64x28x28xf16, {order = #NHWC}> -> tensor<1x64x14x14xf16, {order = #NHWC}>

    return %0 : tensor<1x64x14x14xf16, {order = #NHWC}>

    // CHECK:       [[OUT:%.+]] = VPU.NCE.AveragePool(%arg0)
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, quant_scale = [2.500000e-01]>,
    // CHECK-SAME:      strides = [2, 2]}
    // CHECK-SAME:      -> tensor<1x64x14x14xf16, {order = #NHWC}>

    // CHECK:       return [[OUT]] : tensor<1x64x14x14xf16, {order = #NHWC}>
}

// -----

!qElemType = !quant.uniform<u8:f16, 0.049356617647058822>
!qElemType1 = !quant.uniform<u8:f16, 0.01013327205882353>
!qElemType2 = !quant.uniform<u8:f16, 0.053278186274509802>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @EltwiseAddWithDifferentScales(%arg0: tensor<1x64x28x28x!qElemType, {order = #NHWC}>, %arg1: tensor<1x64x28x28x!qElemType1, {order = #NHWC}>)
func.func @EltwiseAddWithDifferentScales(%arg0: tensor<1x64x28x28x!qElemType, {order = #NHWC}>, %arg1: tensor<1x64x28x28x!qElemType1, {order = #NHWC}>)
        -> tensor<1x64x28x28x!qElemType2, {order = #NHWC}> {
    %0 = IE.Add(%arg0, %arg1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } :
        tensor<1x64x28x28x!qElemType, {order = #NHWC}>, tensor<1x64x28x28x!qElemType1, {order = #NHWC}>
        -> tensor<1x64x28x28x!qElemType2, {order = #NHWC}>

    return %0 : tensor<1x64x28x28x!qElemType2, {order = #NHWC}>

    // CHECK:       [[OUT:%.+]] = VPU.NCE.Eltwise(%arg0, %arg1)
    // CHECK-SAME:      op_type = #VPU.eltwise_type<ADD>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <ADD>, clamp_low = 0 : i64, clamp_high = 255 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, quant_mult = [19219],
    // CHECK-SAME:      quant_shift = [29], quant_post_shift = 0 : i64, in1_quant_mult = [25877], in2_quant_mult = [5312], fp_prelu_alpha = 1.000000e+00 : f64>}
    // CHECK-SAME:      -> tensor<1x64x28x28x!qElemType2, {order = #NHWC}>

    // CHECK:       return [[OUT]] : tensor<1x64x28x28x!qElemType2, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @SkipEltwiseAndToNCE
func.func @SkipEltwiseAndToNCE(%arg0: tensor<1x64x28x28xf16, {order = #NHWC}>, %arg1: tensor<1x64x28x28xf16, {order = #NHWC}>)
        -> tensor<1x64x28x28xf16, {order = #NHWC}> {
    %0 = IE.And(%arg0, %arg1) { auto_broadcast = #IE.auto_broadcast_type<NUMPY> } :
        tensor<1x64x28x28xf16, {order = #NHWC}>, tensor<1x64x28x28xf16, {order = #NHWC}>
        -> tensor<1x64x28x28xf16, {order = #NHWC}>

    return %0 : tensor<1x64x28x28xf16, {order = #NHWC}>

    // CHECK-NOT:   VPU.NCE.Eltwise

    // CHECK:       [[OUT:%.+]] = IE.And(%arg0, %arg1) {auto_broadcast = #IE.auto_broadcast_type<NUMPY>} :
    // CHECK-SAME:      tensor<1x64x28x28xf16, {order = #NHWC}>, tensor<1x64x28x28xf16, {order = #NHWC}>
    // CHECK-SAME:      -> tensor<1x64x28x28xf16, {order = #NHWC}>

    // CHECK:       return [[OUT]] : tensor<1x64x28x28xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @ConvToNCE4channels
func.func @ConvToNCE4channels(%arg0: tensor<1x4x16x16xf16, {order = #NHWC}>) -> tensor<1x16x16x16xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<16x4x1x1xf16, {order = #NHWC}> =
        dense<1.000000e+00> : tensor<16x4x1x1xf16>, [#const.Reorder<#NHWC>]
    %bias = const.Declare tensor<1x16x1x1xf16> = dense<1.000000e+00> : tensor<1x16x1x1xf16>

    %0 = IE.Convolution(%arg0, %weights, %bias) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 0.1}>
        } : tensor<1x4x16x16xf16, {order = #NHWC}>, tensor<16x4x1x1xf16, {order = #NHWC}>, tensor<1x16x1x1xf16>
            -> tensor<1x16x16x16xf16, {order = #NHWC}>

    return %0 : tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<16x1x1x16xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<16x4x1x1xf16>,
    // CHECK-SAME:      [#const.Reorder<#NHWC>, #const.Reshape<[16, 1, 1, 4]>, #const.PadWithZero<[0, 0, 0, 0], [0, 0, 0, 12]>]
    // CHECK-DAG:       [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32>

    // CHECK:       [[VAL0:%.+]] = VPU.NCE.CompressConvolution(%arg0, [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:      cm_sp_pattern = 15 : i64,
    // CHECK-SAME:      pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <LPRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1638 : i64, lrelu_shift = 14 : i64>,
    // CHECK-SAME:      rawFilterShape = [16, 4, 1, 1]
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      -> tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK:       return [[VAL0]] : tensor<1x16x16x16xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 0.078431372549019607>
!qElemType1 = !quant.uniform<u8:f16, 0.039215686274509803>

// CHECK-LABEL: @AddWithDifferentScales
func.func @AddWithDifferentScales(%arg0: tensor<1x16x1x2xui8, {order = #NHWC}>) -> tensor<1x16x1x2xf16, {order = #NHWC}> {
    %cst = const.Declare tensor<1x16x1x2x!qElemType, {order = #NHWC}> =
        dense<1.000000e+00> : tensor<1x16x1x2xf32>, [
            #const.ConvertElemType<f16>,
            #const.ConvertElemType<ui8>,
            #const.QuantCast<!qElemType>,
            #const.Reorder<#NHWC>
        ]

    %0 = IE.QuantizeCast(%arg0) {
        dstElemType = !qElemType1
    } : tensor<1x16x1x2xui8, {order = #NHWC}> -> tensor<1x16x1x2x!qElemType1, {order = #NHWC}>

    %1 = IE.Add(%0, %cst) {
        auto_broadcast = #IE.auto_broadcast_type<NUMPY>
    } : tensor<1x16x1x2x!qElemType1, {order = #NHWC}>, tensor<1x16x1x2x!qElemType, {order = #NHWC}> -> tensor<1x16x1x2xf16, {order = #NHWC}>

    return %1 : tensor<1x16x1x2xf16, {order = #NHWC}>

    // CHECK-DAG:   [[ADD_WEIGHTS:%.*]] = const.Declare tensor<1x16x1x2x!qElemType, {order = #NHWC}> =
    // CHECK-SAME:  dense<1.000000e+00> : tensor<1x16x1x2xf32>, [
    // CHECK-SAME:    #const.ConvertElemType<f16>,
    // CHECK-SAME:    #const.ConvertElemType<ui8>,
    // CHECK-SAME:    #const.QuantCast<!qElemType>,
    // CHECK-SAME:    #const.Reorder<#NHWC>
    // CHECK-SAME:  ]

    // CHECK:   [[QUANT_CAST:%.*]] = IE.QuantizeCast(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType1
    // CHECK-SAME:  } : tensor<1x16x1x2xui8, {order = #NHWC}> -> tensor<1x16x1x2x!qElemType1, {order = #NHWC}>

    // CHECK:   [[NCE_ADD:%.*]] = VPU.NCE.Eltwise([[QUANT_CAST]], [[ADD_WEIGHTS]]) {
    // CHECK-SAME:     op_type = #VPU.eltwise_type<ADD>,
    // CHECK-SAME:     ppe = #VPU.PPETask<mode = <ADD>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64,
    // CHECK-SAME:     quant_mult = [16384], quant_shift = [33], quant_post_shift = 0 : i64, in1_quant_mult = [20560], in2_quant_mult = [41120], fp_prelu_alpha = 1.000000e+00 : f64>
    // CHECK-SAME:     } -> tensor<1x16x1x2xf16, {order = #NHWC}>

    // CHECK:   return [[NCE_ADD]] : tensor<1x16x1x2xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @ConvertPermuteQuantize
func.func @ConvertPermuteQuantize(%arg0: tensor<1x3x224x224xf16>) -> tensor<1x4x224x224x!qElemType, {order = #NHWC}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NHWC,
        mem_perm = #NHWC,
        pads_begin = [0, 0, 0, 0],
        pads_end = [0, 1, 0, 0]
    } : tensor<1x3x224x224xf16> -> tensor<1x4x224x224x!qElemType, {order = #NHWC}>

    return %0 : tensor<1x4x224x224x!qElemType, {order = #NHWC}>

    // CHECK-NOT:   IE.PermuteQuantize

    // CHECK:       [[NCE_PERMUTE:%.*]] = VPU.NCE.Permute(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dstOrder = #NHWC,
    // CHECK-SAME:      expandedChannels = 4 : i64
    // CHECK-SAME:  } -> tensor<1x4x224x224x!qElemType, {order = #NHWC}>

    // CHECK:       return [[NCE_PERMUTE]] : tensor<1x4x224x224x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @PermuteQuantizeDoesNotFitCMX
func.func @PermuteQuantizeDoesNotFitCMX(%arg0: tensor<1x3x512x512xf16>) -> tensor<1x16x512x512x!qElemType, {order = #NHWC}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NHWC,
        mem_perm = #NHWC,
        pads_begin = [0, 0, 0, 0],
        pads_end = [0, 13, 0, 0]
    } : tensor<1x3x512x512xf16> -> tensor<1x16x512x512x!qElemType, {order = #NHWC}>

    return %0 : tensor<1x16x512x512x!qElemType, {order = #NHWC}>

    // CHECK-NOT:   IE.PermuteQuantize

    // CHECK:       [[NCE_PERMUTE:%.*]] = VPU.NCE.Permute(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dstOrder = #NHWC,
    // CHECK-SAME:      expandedChannels = 16 : i64
    // CHECK-SAME:  } -> tensor<1x16x512x512x!qElemType, {order = #NHWC}>

    // CHECK:       return [[NCE_PERMUTE]] : tensor<1x16x512x512x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @PermuteQuantizeStartPadsOverHeight
func.func @PermuteQuantizeStartPadsOverHeight(%arg0: tensor<1x3x224x224xf16>) -> tensor<1x4x225x224x!qElemType, {order = #NHWC}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NHWC,
        mem_perm = #NHWC,
        pads_begin = [0, 0, 1, 0],
        pads_end = [0, 1, 0, 0]
    } : tensor<1x3x224x224xf16> -> tensor<1x4x225x224x!qElemType, {order = #NHWC}>

    return %0 : tensor<1x4x225x224x!qElemType, {order = #NHWC}>

    // CHECK-NOT:   VPU.NCE.Permute
    // CHECK-NOT:   VPU.Reshape
    // CHECK-NOT:   IE.AffineReshape

    // CHECK:       [[PERMUTE_QUANTIZE:%.*]] = IE.PermuteQuantize(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dst_order = #NHWC,
    // CHECK-SAME:      mem_perm = #NHWC,
    // CHECK-SAME:      pads_begin = [0, 0, 1, 0],
    // CHECK-SAME:      pads_end = [0, 1, 0, 0]
    // CHECK-SAME:  } : tensor<1x3x224x224xf16> -> tensor<1x4x225x224x!qElemType, {order = #NHWC}>

    // CHECK:       return [[PERMUTE_QUANTIZE]] : tensor<1x4x225x224x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @PermuteQuantizeEndPadsOverHeight
func.func @PermuteQuantizeEndPadsOverHeight(%arg0: tensor<1x3x224x224xf16>) -> tensor<1x4x225x224x!qElemType, {order = #NHWC}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NHWC,
        mem_perm = #NHWC,
        pads_begin = [0, 0, 0, 0],
        pads_end = [0, 1, 1, 0]
    } : tensor<1x3x224x224xf16> -> tensor<1x4x225x224x!qElemType, {order = #NHWC}>

    return %0 : tensor<1x4x225x224x!qElemType, {order = #NHWC}>

    // CHECK-NOT:   VPU.NCE.Permute
    // CHECK-NOT:   VPU.Reshape
    // CHECK-NOT:   IE.AffineReshape

    // CHECK:       [[PERMUTE_QUANTIZE:%.*]] = IE.PermuteQuantize(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dst_order = #NHWC,
    // CHECK-SAME:      mem_perm = #NHWC,
    // CHECK-SAME:      pads_begin = [0, 0, 0, 0],
    // CHECK-SAME:      pads_end = [0, 1, 1, 0]
    // CHECK-SAME:  } : tensor<1x3x224x224xf16> -> tensor<1x4x225x224x!qElemType, {order = #NHWC}>

    // CHECK:       return [[PERMUTE_QUANTIZE]] : tensor<1x4x225x224x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NCWH = affine_map<(d0, d1, d2, d3) -> (d0, d1, d3, d2)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @PermuteQuantizeUnsupportedInputLayout
func.func @PermuteQuantizeUnsupportedInputLayout(%arg0: tensor<1x3x224x224xf16, {order = #NCWH}>) -> tensor<1x4x224x224x!qElemType, {order = #NHWC}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NHWC,
        mem_perm = #NHWC,
        pads_begin = [0, 0, 0, 0],
        pads_end = [0, 1, 0, 0]
    } : tensor<1x3x224x224xf16, {order = #NCWH}> -> tensor<1x4x224x224x!qElemType, {order = #NHWC}>

    return %0 : tensor<1x4x224x224x!qElemType, {order = #NHWC}>

    // CHECK-NOT:   VPU.NCE.Permute
    // CHECK-NOT:   VPU.Reshape
    // CHECK-NOT:   IE.AffineReshape

    // CHECK:       [[PERMUTE_QUANTIZE:%.*]] = IE.PermuteQuantize(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dst_order = #NHWC,
    // CHECK-SAME:      mem_perm = #NHWC,
    // CHECK-SAME:      pads_begin = [0, 0, 0, 0],
    // CHECK-SAME:      pads_end = [0, 1, 0, 0]
    // CHECK-SAME:  } : tensor<1x3x224x224xf16, {order = #NCWH}> -> tensor<1x4x224x224x!qElemType, {order = #NHWC}>

    // CHECK:       return [[PERMUTE_QUANTIZE]] : tensor<1x4x224x224x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
#NWCH = affine_map<(d0, d1, d2, d3) -> (d0, d3, d1, d2)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @PermuteQuantizeUnsupportedOutputLayout
func.func @PermuteQuantizeUnsupportedOutputLayout(%arg0: tensor<1x3x224x224xf16>) -> tensor<1x4x224x224x!qElemType, {order = #NWCH}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NWCH,
        mem_perm = #NWCH,
        pads_begin = [0, 0, 0, 0],
        pads_end = [0, 1, 0, 0]
    } : tensor<1x3x224x224xf16> -> tensor<1x4x224x224x!qElemType, {order = #NWCH}>

    return %0 : tensor<1x4x224x224x!qElemType, {order = #NWCH}>

    // CHECK-NOT:   VPU.NCE.Permute
    // CHECK-NOT:   VPU.Reshape
    // CHECK-NOT:   IE.AffineReshape

    // CHECK:       [[PERMUTE_QUANTIZE:%.*]] = IE.PermuteQuantize(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dst_order = #NWCH,
    // CHECK-SAME:      mem_perm = #NWCH,
    // CHECK-SAME:      pads_begin = [0, 0, 0, 0],
    // CHECK-SAME:      pads_end = [0, 1, 0, 0]
    // CHECK-SAME:  } : tensor<1x3x224x224xf16> -> tensor<1x4x224x224x!qElemType, {order = #NWCH}>

    // CHECK:       return [[PERMUTE_QUANTIZE]] : tensor<1x4x224x224x!qElemType, {order = #NWCH}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 1.000000e+00>

// CHECK-LABEL: @PermuteQuantizeUnsupportedShape
func.func @PermuteQuantizeUnsupportedShape(%arg0: tensor<1x3x225x225xf16>) -> tensor<1x4x225x225x!qElemType, {order = #NHWC}> {
    %0 = IE.PermuteQuantize(%arg0) {
        dstElemType = !qElemType,
        dst_order = #NHWC,
        mem_perm = #NHWC,
        pads_begin = [0, 0, 0, 0],
        pads_end = [0, 1, 0, 0]
    } : tensor<1x3x225x225xf16> -> tensor<1x4x225x225x!qElemType, {order = #NHWC}>

    return %0 : tensor<1x4x225x225x!qElemType, {order = #NHWC}>

    // CHECK-NOT:   VPU.NCE.Permute
    // CHECK-NOT:   VPU.Reshape
    // CHECK-NOT:   IE.AffineReshape

    // CHECK:       [[PERMUTE_QUANTIZE:%.*]] = IE.PermuteQuantize(%arg0) {
    // CHECK-SAME:      dstElemType = !qElemType,
    // CHECK-SAME:      dst_order = #NHWC,
    // CHECK-SAME:      mem_perm = #NHWC,
    // CHECK-SAME:      pads_begin = [0, 0, 0, 0],
    // CHECK-SAME:      pads_end = [0, 1, 0, 0]
    // CHECK-SAME:  } : tensor<1x3x225x225xf16> -> tensor<1x4x225x225x!qElemType, {order = #NHWC}>

    // CHECK:       return [[PERMUTE_QUANTIZE]] : tensor<1x4x225x225x!qElemType, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

func.func @ClampLowInF16PReLU(%arg0: tensor<1x16x128x128xf16, {order = #NHWC}>) -> tensor<1x64x64x64xf16, {order = #NHWC}> {
    %WEIGHTS = const.Declare tensor<64x16x3x3xf16, {order = #NHWC}> = dense<1.0> : tensor<64x16x3x3xf16, {order = #NHWC}>
    %CONV = IE.Convolution(%arg0, %WEIGHTS) {
        dilations = [1, 1],
        pads_begin = [1, 1],
        pads_end = [0, 0],
        post_op = #IE.PostOp<
            attrs = {
                negative_slope = -2.312500e+00 : f64
            },
            name = "IE.LeakyRelu"
        >,
        strides = [2, 2]
    } : tensor<1x16x128x128xf16, {order = #NHWC}>, tensor<64x16x3x3xf16, {order = #NHWC}> -> tensor<1x64x64x64xf16, {order = #NHWC}>

    // CHECK:   clamp_low = -2147483648 : i64

    return %CONV : tensor<1x64x64x64xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @ConvToNCECompressConv
func.func @ConvToNCECompressConv(%arg0: tensor<1x4x16x16xf16, {order = #NHWC}>) -> tensor<1x16x16x16xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<16x4x1x1xf16, {order = #NHWC}> =
        dense<1.000000e+00> : tensor<16x3x1x1xf16>, [#const.Reorder<#NHWC>, #const.PadWithZero<[0, 0, 0, 0], [0, 1, 0, 0]>]
    %bias = const.Declare tensor<1x16x1x1xf16> = dense<1.000000e+00> : tensor<1x16x1x1xf16>

    %0 = IE.Convolution(%arg0, %weights, %bias) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 0.1}>
        } : tensor<1x4x16x16xf16, {order = #NHWC}>, tensor<16x4x1x1xf16, {order = #NHWC}>, tensor<1x16x1x1xf16>
            -> tensor<1x16x16x16xf16, {order = #NHWC}>

    return %0 : tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<16x1x1x16xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<16x3x1x1xf16>,
    // CHECK-SAME:          [#const.Reorder<#NHWC>, #const.PadWithZero<[0, 0, 0, 0], [0, 1, 0, 0]>,
    // CHECK-SAME:          #const.SubView<[0, 0, 0, 0], [16, 3, 1, 1]>, #const.Reshape<[16, 1, 1, 3]>,
    // CHECK-SAME:          #const.PadWithZero<[0, 0, 0, 0], [0, 0, 0, 13]>]
    // CHECK-DAG:       [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32>

    // CHECK:       [[VAL0:%.+]] = VPU.NCE.CompressConvolution(%arg0, [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:      cm_sp_pattern = 7 : i64,
    // CHECK-SAME:      pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <LPRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1638 : i64, lrelu_shift = 14 : i64>,
    // CHECK-SAME:      rawFilterShape = [16, 3, 1, 1]
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      -> tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK:       return [[VAL0]] : tensor<1x16x16x16xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @ConvToNCECompressConvWithPadBefore
func.func @ConvToNCECompressConvWithPadBefore(%arg0: tensor<1x4x16x16xf16, {order = #NHWC}>) -> tensor<1x16x16x16xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<16x4x1x1xf16, {order = #NHWC}> =
        dense<1.000000e+00> : tensor<16x3x1x1xf16>, [#const.Reorder<#NHWC>, #const.PadWithZero<[0, 1, 0, 0], [0, 0, 0, 0]>]
    %bias = const.Declare tensor<1x16x1x1xf16> = dense<1.000000e+00> : tensor<1x16x1x1xf16>

    %0 = IE.Convolution(%arg0, %weights, %bias) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 0.1}>
        } : tensor<1x4x16x16xf16, {order = #NHWC}>, tensor<16x4x1x1xf16, {order = #NHWC}>, tensor<1x16x1x1xf16>
            -> tensor<1x16x16x16xf16, {order = #NHWC}>

    return %0 : tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<16x1x1x16xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<16x3x1x1xf16>,
    // CHECK-SAME:          [#const.Reorder<#NHWC>, #const.PadWithZero<[0, 1, 0, 0], [0, 0, 0, 0]>,
    // CHECK-SAME:           #const.Reshape<[16, 1, 1, 4]>, #const.PadWithZero<[0, 0, 0, 0], [0, 0, 0, 12]>]
    // CHECK-DAG:       [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32>

    // CHECK:       [[VAL0:%.+]] = VPU.NCE.CompressConvolution(%arg0, [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:      cm_sp_pattern = 15 : i64,
    // CHECK-SAME:      pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:      ppe = #VPU.PPETask<mode = <LPRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1638 : i64, lrelu_shift = 14 : i64>,
    // CHECK-SAME:      rawFilterShape = [16, 4, 1, 1]
    // CHECK-SAME:      strides = [1, 1]
    // CHECK-SAME:      -> tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK:       return [[VAL0]] : tensor<1x16x16x16xf16, {order = #NHWC}>
}


// -----
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @DepthConvToNCEWithWeightsAlign
func.func @DepthConvToNCEWithWeightsAlign(%arg0: tensor<1x16x40x80xf16, {order = #NHWC}>, %arg1: tensor<16x1x2x3xf16, {order = #NHWC}>) -> tensor<1x16x39x78xf16, {order = #NHWC}> {
    %0 = IE.GroupConvolution(%arg0, %arg1) {
            dilations = [1, 1],
            groups = 16,
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 0.1}>
        } : tensor<1x16x40x80xf16, {order = #NHWC}>, tensor<16x1x2x3xf16, {order = #NHWC}>
            -> tensor<1x16x39x78xf16, {order = #NHWC}>

    return %0 : tensor<1x16x39x78xf16, {order = #NHWC}>


    // CHECK-DAG:   [[CONST0:%.+]] = const.Declare tensor<16x10x1x1xf16> = dense<0.000000e+00> : tensor<16x10x1x1xf16>
    // CHECK-DAG:   [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32>

    // CHECK-DAG:   [[SHAPECAST:%.+]] = IE.ShapeCast {shape = [16, 6, 1, 1]} inputs(%arg1 : tensor<16x1x2x3xf16, {order = #NHWC}>) -> tensor<16x6x1x1xf16, {order = #NHWC}>
    // CHECK-DAG:   [[PERMUTECAST:%.+]] = IE.PermuteCast([[SHAPECAST]]) {dst_order = #NCHW, mem_perm = #NWCH} : tensor<16x6x1x1xf16, {order = #NHWC}> -> tensor<16x6x1x1xf16>
    // CHECK-DAG:   [[CONCAT:%.+]] = IE.Concat([[PERMUTECAST]], [[CONST0]]) {per_axis = #IE.Concat<axis = 1 : i64>} : tensor<16x6x1x1xf16>, tensor<16x10x1x1xf16> -> tensor<16x16x1x1xf16>
    // CHECK-DAG:   [[PERMUTECAST1:%.+]] = IE.PermuteCast([[CONCAT]]) {dst_order = #NHWC, mem_perm = #NHWC} : tensor<16x16x1x1xf16> -> tensor<16x16x1x1xf16, {order = #NHWC}>
    // CHECK:       [[DEPTHCONV:%.+]] = VPU.NCE.DepthConvolution(%arg0, [[PERMUTECAST1]], [[WEIGHTS_TABLE]])

    // CHECK:       return [[DEPTHCONV:%.+]] : tensor<1x16x39x78xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @AvgPoolToNCE
func.func @AvgPoolToNCE(%arg0: tensor<1x16x6x6xf16, {order = #NHWC}>) -> tensor<1x16x4x4xf16, {order = #NHWC}> {
    %ave_pool = IE.AvgPool(%arg0) {
        exclude_pads,
        kernel_size = [3, 3],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        rounding_type = #IE.rounding_type<FLOOR>,
        strides = [1, 1]
    } : tensor<1x16x6x6xf16, {order = #NHWC}> -> tensor<1x16x4x4xf16, {order = #NHWC}>

    return %ave_pool : tensor<1x16x4x4xf16, {order = #NHWC}>

    // CHECK:         [[OUT:%.+]] = VPU.NCE.AveragePool(%arg0) {kernel_size = [3, 3], pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>, ppe = #VPU.PPETask<mode = <NOOP>,
    // CHECK-SAME:          clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, quant_scale = [0.1111111111111111]>, strides = [1, 1]} -> tensor<1x16x4x4xf16, {order = #NHWC}>
    // CHECK:           return [[OUT]] : tensor<1x16x4x4xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @NotConvertAvgPoolToNCE
func.func @NotConvertAvgPoolToNCE(%arg0: tensor<1x16x6x6xf16, {order = #NHWC}>) -> tensor<1x16x5x4xf16, {order = #NHWC}> {
    %ave_pool = IE.AvgPool(%arg0) {
        exclude_pads,
        kernel_size = [3, 3],
        pads_begin = [1, 0],
        pads_end = [0, 0],
        rounding_type = #IE.rounding_type<FLOOR>,
        strides = [1, 1]
    } : tensor<1x16x6x6xf16, {order = #NHWC}> -> tensor<1x16x5x4xf16, {order = #NHWC}>

    return %ave_pool : tensor<1x16x5x4xf16, {order = #NHWC}>

    // CHECK:         [[OUT:%.+]] = IE.AvgPool(%arg0) {exclude_pads, kernel_size = [3, 3], pads_begin = [1, 0], pads_end = [0, 0], rounding_type = #IE.rounding_type<FLOOR>, strides = [1, 1]} : tensor<1x16x6x6xf16, {order = #NHWC}> -> tensor<1x16x5x4xf16, {order = #NHWC}>
    // CHECK:           return [[OUT]] : tensor<1x16x5x4xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
!qElemType = !quant.uniform<i8:f16, 0.078737745098039214>

// CHECK-LABEL: @BiasFuncForI8Weights
func.func @BiasFuncForI8Weights(%arg0: tensor<1x16x16x16xf16, {order = #NHWC}>) -> tensor<1x16x16x16xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<16x16x1x1x!qElemType, {order = #NHWC}> =
        dense<1.000000e+00> : tensor<16x16x1x1xf16>, [#const.ConvertElemType<si8>, #const.QuantCast<!qElemType>, #const.Reorder<#NHWC>]
    %bias = const.Declare tensor<1x16x1x1xf16> = dense<1.000000e+00> : tensor<1x16x1x1xf16>

    %0 = IE.Convolution(%arg0, %weights, %bias) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1],
            post_op = #IE.PostOp<name = "IE.LeakyRelu", attrs = {negative_slope = 0.1}>
        } : tensor<1x16x16x16xf16, {order = #NHWC}>, tensor<16x16x1x1x!qElemType, {order = #NHWC}>, tensor<1x16x1x1xf16>
            -> tensor<1x16x16x16xf16, {order = #NHWC}>

    return %0 : tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<16x16x1x1x!qElemType, {order = #NHWC}> = dense<1.000000e+00> : tensor<16x16x1x1xf16>, [#const.ConvertElemType<si8>, #const.QuantCast<!qElemType>, #const.Reorder<#NHWC>]
    // CHECK-DAG:       [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32>
    // CHECK-SAME:          0, 0, 1033978177, 1095447755
    // CHECK-SAME:          16, 0, 1033978177, 1095447755
    // CHECK-SAME:          32, 0, 1033978177, 1095447755
    // CHECK-SAME:          48, 0, 1033978177, 1095447755
    // CHECK-SAME:          64, 0, 1033978177, 1095447755
    // CHECK-SAME:          80, 0, 1033978177, 1095447755
    // CHECK-SAME:          96, 0, 1033978177, 1095447755
    // CHECK-SAME:          112, 0, 1033978177, 1095447755
    // CHECK-SAME:          128, 0, 1033978177, 1095447755
    // CHECK-SAME:          144, 0, 1033978177, 1095447755
    // CHECK-SAME:          160, 0, 1033978177, 1095447755
    // CHECK-SAME:          176, 0, 1033978177, 1095447755
    // CHECK-SAME:          192, 0, 1033978177, 1095447755
    // CHECK-SAME:          208, 0, 1033978177, 1095447755
    // CHECK-SAME:          224, 0, 1033978177, 1095447755
    // CHECK-SAME:          240, 0, 1033978177, 1095447755
    // CHECK-SAME:          : tensor<16x1x1x4xsi32>


    // CHECK:       [[VAL0:%.+]] = VPU.NCE.Convolution(%arg0, [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:      -> tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK:       return [[VAL0]] : tensor<1x16x16x16xf16, {order = #NHWC}>
}

// -----

!qElemType = !quant.uniform<i4:f16, 1.3385416666666667>
#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @I4WeightsConvToNCE
func.func @I4WeightsConvToNCE(%arg0: tensor<1x16x16x16xf16, {order = #NHWC}>) -> tensor<1x16x16x16xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<16x16x1x1x!qElemType, {order = #NHWC}> = dense<1.000000e+00> :
        tensor<16x16x1x1xf16>, [#const.ConvertElemType<si4>, #const.QuantCast<!qElemType>, #const.Reorder<#NHWC>]

    %0 = IE.Convolution(%arg0, %weights) {
            dilations = [1, 1],
            pads_begin = [0, 0],
            pads_end = [0, 0],
            strides = [1, 1]
        } : tensor<1x16x16x16xf16, {order = #NHWC}>, tensor<16x16x1x1x!qElemType, {order = #NHWC}>
            -> tensor<1x16x16x16xf16, {order = #NHWC}>

    return %0 : tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK-DAG:       [[WEIGHTS:%.+]] = const.Declare tensor<16x1x1x32x!qElemType, {order = #NHWC}> = dense<1.000000e+00> :
    // CHECK-SAME:      tensor<16x16x1x1xf16>, [#const.ConvertElemType<si4>, #const.QuantCast<!qElemType>, #const.Reorder<#NHWC>, #const.Reshape<[16, 1, 1, 16]>, #const.PadWithZero<[0, 0, 0, 0], [0, 0, 0, 16]>]
    // CHECK-DAG:       [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<16x1x1x4xsi32> =
    // CHECK-SAME{LITERAL}:    dense<[[[[0, 0, 1068193109, 0]]], [[[16, 0, 1068193109, 0]]], [[[32, 0, 1068193109, 0]]], [[[48, 0, 1068193109, 0]]], [[[64, 0, 1068193109, 0]]], [[[80, 0, 1068193109, 0]]], [[[96, 0, 1068193109, 0]]], [[[112, 0, 1068193109, 0]]], [[[128, 0, 1068193109, 0]]], [[[144, 0, 1068193109, 0]]], [[[160, 0, 1068193109, 0]]], [[[176, 0, 1068193109, 0]]], [[[192, 0, 1068193109, 0]]], [[[208, 0, 1068193109, 0]]], [[[224, 0, 1068193109, 0]]], [[[240, 0, 1068193109, 0]]]]> : tensor<16x1x1x4xsi32>
    // CHECK:       [[VAL0:%.+]] = VPU.NCE.Convolution(%arg0, [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:    {pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:    rawFilterShape = [16, 16, 1, 1], strides = [1, 1]} -> tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK:       return [[VAL0]] : tensor<1x16x16x16xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @ConvWithStaticScale
// CHECK-SAME: ([[ARG0:%.+]]: tensor<1x16x16x16xf16, {order = #NHWC}>,
// CHECK-SAME:  [[ARG1:%.+]]: tensor<16x16x1x1xf16, {order = #NHWC}>)
func.func @ConvWithStaticScale(%arg0: tensor<1x16x16x16xf16, {order = #NHWC}>,
                               %arg1: tensor<16x16x1x1xf16, {order = #NHWC}>)
        -> tensor<1x16x16x16xf16, {order = #NHWC}> {

    %0 = IE.Convolution(%arg0, %arg1) {
        dilations = [1, 1],
        pads_begin = [0, 0],
        pads_end = [0, 0],
        strides = [1, 1],
        // Note: 5.24156e-40 is '374050' when bit-cast to int
        static_scale = 5.24156e-40 : f32
    } : tensor<1x16x16x16xf16, {order = #NHWC}>, tensor<16x16x1x1xf16, {order = #NHWC}>
        -> tensor<1x16x16x16xf16, {order = #NHWC}>

    return %0 : tensor<1x16x16x16xf16, {order = #NHWC}>

    // CHECK:   [[WEIGHTS:%.+]] = const.Declare tensor<16x1x1x4xsi32> = dense<[
    // CHECK-SAME{LITERAL}: [[[0, 0, 374050, 0]]], [[[32, 0, 374050, 0]]],
    // CHECK-SAME{LITERAL}: [[[448, 0, 374050, 0]]], [[[480, 0, 374050, 0]]]
    // CHECK-SAME:  ]> : tensor<16x1x1x4xsi32>

    // CHECK:   [[OUT:%.+]] = VPU.NCE.Convolution([[ARG0]], [[ARG1]], [[WEIGHTS]])

    // CHECK:       return [[OUT]]
}
