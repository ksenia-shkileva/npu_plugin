//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --tiling-strategy-assignment="tiling-mode=ISOLATED vpunn-cost=true" %s | FileCheck %s
// REQUIRES: arch-NPU40XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL:   @SplitNCEConvOverC
// CHECK-SAME:          [[INPUT:%arg[0-9]]]: tensor<1x32x64x48xf16, {order = #NHWC}>
func.func @SplitNCEConvOverC(%arg0: tensor<1x32x64x48xf16, {order = #NHWC}>) -> tensor<1x256x64x48xf16, {order = #NHWC}> {
    %weights = const.Declare tensor<256x32x3x3xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<256x32x3x3xf16>, [#const.Reorder<#NHWC>]
    %weights_table = const.Declare tensor<256x1x1x4xsi32> = dense<1> : tensor<256x1x1x4xsi32>

    %0 = VPU.NCE.Convolution(%arg0, %weights, %weights_table) {
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        rawFilterShape = [256, 32, 3, 3],
        strides = [1, 1]
    } -> tensor<1x256x64x48xf16, {order = #NHWC}>

    return %0 : tensor<1x256x64x48xf16, {order = #NHWC}>

    // CHECK-DAG:        [[FILTER:%.+]] = const.Declare tensor<256x32x3x3xf16, {order = #NHWC}> = dense<1.000000e+00>
    // CHECK-SAME:      : tensor<256x32x3x3xf16>, [#const.Reorder<#NHWC>]

    // CHECK-DAG:        [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<256x1x1x4xsi32> = dense<1>
    // CHECK-SAME:      : tensor<256x1x1x4xsi32>

    // CHECK:        [[CONV:%.+]] = VPU.NCE.Convolution([[INPUT]], [[FILTER]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:          pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:          rawFilterShape = [256, 32, 3, 3], strides = [1, 1], tilingStrategy = [1, 2, 1, 1]
    // CHECK-SAME:          -> tensor<1x256x64x48xf16, {order = #NHWC}>

    // CHECK:        return [[CONV]] : tensor<1x256x64x48xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 0.96372549019607844>
!qElemType1 = !quant.uniform<u8:f16, 0.054779411764705882>
!qElemType2 = !quant.uniform<u8<0:254>:f16, 8.7179349163385824E-4:127>

// CHECK-LABEL:   @SplitQuantNCEConvOverW
// CHECK-SAME:          [[INPUT:%arg[0-9]]]: tensor<1x32x64x64x!qElemType, {order = #NHWC}>
func.func @SplitQuantNCEConvOverW(%arg0: tensor<1x32x64x64x!qElemType, {order = #NHWC}>) -> tensor<1x512x64x64x!qElemType1, {order = #NHWC}> {
    %weights = const.Declare tensor<512x32x3x3x!qElemType2, {order = #NHWC}> = dense<1.000000e+00> : tensor<512x32x3x3xf16>, [#const.ConvertElemType<ui8>, #const.QuantCast<!qElemType2>, #const.Reorder<#NHWC>]
    %weights_table = const.Declare tensor<512x1x1x4xsi32, {order = #NCHW}> = dense<10> : tensor<512x1x1x4xsi32>

    %0 = VPU.NCE.Convolution(%arg0, %weights, %weights_table) {
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        rawFilterShape = [512, 32, 3, 3],
        strides = [1, 1]
    } -> tensor<1x512x64x64x!qElemType1, {order = #NHWC}>

    return %0 : tensor<1x512x64x64x!qElemType1, {order = #NHWC}>

    // CHECK-DAG:        [[WEIGHTS:%.+]] = const.Declare tensor<512x32x3x3x!qElemType2, {order = #NHWC}> = dense<1.000000e+00>
    // CHECK-SAME:      : tensor<512x32x3x3xf16>, [#const.ConvertElemType<ui8>, #const.QuantCast<!qElemType2>, #const.Reorder<#NHWC>]

    // CHECK-DAG:        [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<512x1x1x4xsi32, {order = #NCHW}> = dense<10>
    // CHECK-SAME:      : tensor<512x1x1x4xsi32>

    // CHECK:        [[CONV:%.+]] = VPU.NCE.Convolution([[INPUT]], [[WEIGHTS]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:          pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:          rawFilterShape = [512, 32, 3, 3], strides = [1, 1], tilingStrategy = [1, 1, 1, 2]
    // CHECK-SAME:          -> tensor<1x512x64x64x!qElemType1, {order = #NHWC}>

    // CHECK:        return [[CONV]] : tensor<1x512x64x64x!qElemType1, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @SplitNCEMaxPoolOverW
// CHECK-SAME:      [[INPUT:%arg[0-9]]]: tensor<1x16x200x200xf16, {order = #NHWC}>)
func.func @SplitNCEMaxPoolOverW(%arg0: tensor<1x16x200x200xf16, {order = #NHWC}>) -> tensor<1x16x200x200xf16, {order = #NHWC}> {
    %0 = VPU.NCE.MaxPool(%arg0) {
        kernel_size = [3, 3],
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        strides = [1, 1]
    } -> tensor<1x16x200x200xf16, {order = #NHWC}>

    return %0 : tensor<1x16x200x200xf16, {order = #NHWC}>

    // CHECK:       [[MAXPOOL:%.+]] = VPU.NCE.MaxPool([[INPUT]]) {
    // CHECK-SAME:      pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:      tilingStrategy = [1, 1, 1, 2]
    // CHECK-SAME:      } -> tensor<1x16x200x200xf16, {order = #NHWC}>

    // CHECK:       return [[MAXPOOL]] : tensor<1x16x200x200xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: func.func @SplitNCEEltwiseAddOverW
// CHECK-SAME:        [[INPUT1:%arg[0-9]]]: tensor<1x1024x24x16xf16, {order = #NHWC}>,
// CHECK-SAME:        [[INPUT2:%arg[0-9]]]: tensor<1x1024x24x16xf16, {order = #NHWC}>
func.func @SplitNCEEltwiseAddOverW(
        %arg0: tensor<1x1024x24x16xf16, {order = #NHWC}>,
        %arg1: tensor<1x1024x24x16xf16, {order = #NHWC}>)
            -> tensor<1x1024x24x16xf16, {order = #NHWC}> {
    %0 = VPU.NCE.Eltwise(%arg0, %arg1) {
        op_type = #VPU.eltwise_type<ADD>,
        ppe = #VPU.PPETask<clamp_high = 2147483647 : i64, clamp_low = -2147483648 : i64, lrelu_mult = 1 : i64,
               lrelu_shift = 0 : i64,
               mode = <ADD>>
    } -> tensor<1x1024x24x16xf16, {order = #NHWC}>

    return %0 : tensor<1x1024x24x16xf16, {order = #NHWC}>

    // CHECK:       [[ELTWISE:%.+]] = VPU.NCE.Eltwise([[INPUT1]], [[INPUT2]])
    // CHECK-SAME:      op_type = #VPU.eltwise_type<ADD>
    // CHECK-SAME:      tilingStrategy = [1, 1, 1, 2]
    // CHECK-SAME:      -> tensor<1x1024x24x16xf16, {order = #NHWC}>

    // CHECK:       return [[ELTWISE]] : tensor<1x1024x24x16xf16, {order = #NHWC}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

// CHECK-LABEL: @SplitNCEEltwiseAddSameInput
// CHECK-SAME:      [[INPUT:%arg[0-9]]]: tensor<1x2048x14x14xf16, {order = #NHWC}>
func.func @SplitNCEEltwiseAddSameInput(%arg0: tensor<1x2048x14x14xf16, {order = #NHWC}>) -> tensor<1x2048x14x14xf16, {order = #NHWC}> {
    %0 = VPU.NCE.Eltwise(%arg0, %arg0) {
        op_type = #VPU.eltwise_type<ADD>,
        ppe = #VPU.PPETask<clamp_high = 2147483647 : i64, clamp_low = -2147483648 : i64, lrelu_mult = 1 : i64,
               lrelu_shift = 0 : i64,
               mode = <ADD>>
    } -> tensor<1x2048x14x14xf16, {order = #NHWC}>

    return %0 : tensor<1x2048x14x14xf16, {order = #NHWC}>

    // CHECK:       [[ELTWISE:%.+]] = VPU.NCE.Eltwise([[INPUT]], [[INPUT]]) {
    // CHECK-SAME:      op_type = #VPU.eltwise_type<ADD>
    // CHECK-SAME:      tilingStrategy = [1, 1, 2, 1]
    // CHECK-SAME:      } -> tensor<1x2048x14x14xf16, {order = #NHWC}>

    // CHECK:       return [[ELTWISE]] : tensor<1x2048x14x14xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!qElemType = !quant.uniform<u8:f16, 0.96372549019607844>
!qElemType1 = !quant.uniform<u8:f16, 0.054779411764705882>
!qElemType2 = !quant.uniform<u8<0:254>:f16, 8.7179349163385824E-4:127>

// CHECK-LABEL:   @SplitSparseQuantNCEConvOverC
// CHECK-SAME:          [[INPUT:%arg[0-9]]]: tensor<1x32x80x80x!qElemType, {order = #NHWC}>
func.func @SplitSparseQuantNCEConvOverC(%arg0: tensor<1x32x80x80x!qElemType, {order = #NHWC}>) -> tensor<1x320x80x80x!qElemType1, {order = #NHWC}> {
    %weights = const.Declare tensor<320x32x3x3x!qElemType2, {order = #NHWC}> = dense<1.000000e+00> : tensor<320x32x3x3xf16>, [#const.ConvertElemType<ui8>, #const.QuantCast<!qElemType2>, #const.Reorder<#NHWC>, #const.Sparsify<false>]
    %weights_sm = const.Declare tensor<320x1x1x384xi1> = dense<1.000000e+00> : tensor<320x32x3x3xf16>, [#const.Reorder<#NHWC>, #const.GetSparsityMap]
    %weights_sparse = VPU.GroupSparseTensor(%weights, %weights_sm) {sparsity_compression = #VPU.SparsityCompression<axis = 0 : i64, numElems = dense<1> : tensor<320xi64>, alignment = 16 : i64>, is_weights}
        -> !VPU.SparseTensor<data=tensor<320x32x3x3x!qElemType2, {order = #NHWC}>, sparsity_map=tensor<320x1x1x384xi1>, is_weights, #VPU.SparsityCompression<axis = 0 : i64, numElems = dense<1> : tensor<320xi64>, alignment = 16 : i64>>
    %weights_table = const.Declare tensor<320x1x1x4xsi32, {order = #NCHW}> = dense<10> : tensor<320x1x1x4xsi32>

    %0 = VPU.NCE.Convolution(%arg0, %weights_sparse, %weights_table) {
        pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
        rawFilterShape = [320, 32, 3, 3],
        strides = [1, 1]
    } -> tensor<1x320x80x80x!qElemType1, {order = #NHWC}>

    return %0 : tensor<1x320x80x80x!qElemType1, {order = #NHWC}>

    // CHECK-DAG:        [[WEIGHTS:%.+]] = const.Declare tensor<320x32x3x3x!qElemType2, {order = #NHWC}> = dense<1.000000e+00>
    // CHECK-SAME:      : tensor<320x32x3x3xf16>, [#const.ConvertElemType<ui8>, #const.QuantCast<!qElemType2>, #const.Reorder<#NHWC>, #const.Sparsify<false>]

    // CHECK-DAG:        [[WEIGHTS_SM:%.+]] = const.Declare tensor<320x1x1x384xi1> = dense<1.000000e+00>
    // CHECK-SAME:      : tensor<320x32x3x3xf16>, [#const.Reorder<#NHWC>, #const.GetSparsityMap]

    // CHECK:        [[WEIGHTS_SPARSE:%.+]] = VPU.GroupSparseTensor([[WEIGHTS]], [[WEIGHTS_SM]]) {is_weights, sparsity_compression = #VPU.SparsityCompression<axis = 0 : i64, numElems = dense<1> : tensor<320xi64>, alignment = 16 : i64>} -> !VPU.SparseTensor<
    // CHECK-SAME:       data=tensor<320x32x3x3x!qElemType2, {order = #NHWC}>,
    // CHECK-SAME:       sparsity_map=tensor<320x1x1x384xi1>, is_weights

    // CHECK-DAG:        [[WEIGHTS_TABLE:%.+]] = const.Declare tensor<320x1x1x4xsi32, {order = #NCHW}> = dense<10>
    // CHECK-SAME:      : tensor<320x1x1x4xsi32>

    // CHECK:        [[OUTPUT:%.+]] = VPU.NCE.Convolution([[INPUT]], [[WEIGHTS_SPARSE]], [[WEIGHTS_TABLE]])
    // CHECK-SAME:          pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:          rawFilterShape = [320, 32, 3, 3], strides = [1, 1], tilingStrategy = [1, 2, 1, 1]
    // CHECK-SAME:          -> tensor<1x320x80x80x!qElemType1, {order = #NHWC}>

    // CHECK:        return [[OUTPUT]] : tensor<1x320x80x80x!qElemType1, {order = #NHWC}>
}
