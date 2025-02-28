//
// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --cmx-concat="support-nce-op-insertion=true" --canonicalize %s | FileCheck %s
// REQUIRES: arch-NPU40XX

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConvInputDistributed = !VPU.DistributedTensor<
    1x128x16x157xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    memory_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]
}>

!ConcatInputConvOutputDistributed = !VPU.DistributedTensor<
    1x128x16x157xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 8, 157], [1, 128, 8, 157]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]],
    memory_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]
}>

!ConcatOutputDistributed = !VPU.DistributedTensor<
    1x128x16x158xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 9, 158], [1, 128, 9, 158]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    memory_shapes = [[1, 128, 9, 158], [1, 128, 9, 158]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]
}>

!SecondConvOutputDistributed = !VPU.DistributedTensor<
    1x128x16x158xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 8, 158], [1, 128, 8, 158]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]],
    memory_shapes = [[1, 128, 8, 158], [1, 128, 8, 158]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]]
}>

!ConvInput_DDR = tensor<1x128x16x157xf16, {mem_space = @DDR, order = #NHWC}>

!ConvInputStub_CMX = tensor<1x128x16x157xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvOutputStub_CMX = tensor<1x128x16x157xf16, {mem_space = @CMX_NN, order = #NHWC}>

func.func @ConcatClusterTilingWithExplicitDistributedAttrAndConstantSecondInput(%arg0: !ConvInput_DDR,
        %weights0: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1: tensor<128x128x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> !SecondConvOutputDistributed {

    %constInput = const.Declare tensor<1x128x16x1xf16, {order = #NHWC}> = dense<0.000000e+00> :
        tensor<1x128x16x1xf16>, [#const.Reorder<#NHWC>]

    %inputCMX = VPU.NCE.ClusterTiling(%arg0 as %arg1: !ConvInput_DDR) -> !ConvInputDistributed {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInput_DDR -> !ConvInputStub_CMX
        VPU.Yield %0
    }

    %convOutput = VPU.NCE.ClusterTiling (
        %inputCMX as %arg2: !ConvInputStub_CMX,
        %weights0 as %arg3: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg4: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConcatInputConvOutputDistributed {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 1, bottom = 1>,
            ppe = #VPU.PPETask<mode = <LPRELU>, clamp_high = 2147483647 : i64, clamp_low = -2147483648 : i64, lrelu_mult = 1310 : i64, lrelu_shift = 17 : i64,fp_prelu_alpha = 0.0099945068359375 : f64>,
            rawFilterShape = [128, 128, 3, 1], strides = [1, 1]} -> !ConvOutputStub_CMX
        VPU.Yield %0
    }

    %convOutDDR = VPU.NCE.ClusterTiling (%convOutput as %arg5: !ConvOutputStub_CMX) -> tensor<1x128x16x157xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg5) : !ConvOutputStub_CMX -> tensor<1x128x16x157xf16, {order = #NHWC}>
        VPU.Yield %0
    }

    %concatOut = VPU.Concat(%constInput, %convOutDDR) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 1]]} :
        tensor<1x128x16x1xf16, {order = #NHWC}>, tensor<1x128x16x157xf16, {order = #NHWC}> -> tensor<1x128x16x158xf16, {order = #NHWC}>

    %concatOutCMX = VPU.NCE.ClusterTiling (%concatOut as %arg6: tensor<1x128x16x158xf16, {order = #NHWC}>) -> !ConcatOutputDistributed {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : tensor<1x128x16x158xf16, {order = #NHWC}>
            -> tensor<1x128x16x158xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    %output = VPU.NCE.ClusterTiling (
        %concatOutCMX as %arg7: tensor<1x128x16x158xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1 as %arg8: tensor<128x128x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable as %arg9: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !SecondConvOutputDistributed {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 1 , right = 1, top = 1, bottom = 1>,
            ppe = #VPU.PPETask<mode = <LPRELU>, clamp_high = 2147483647 : i64, clamp_low = -2147483648 : i64, lrelu_mult = 1310 : i64, lrelu_shift = 17 : i64,fp_prelu_alpha = 0.0099945068359375 : f64>,
            rawFilterShape = [128, 128, 3, 3], strides = [1, 1]} -> tensor<1x128x16x158xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    return %output: !SecondConvOutputDistributed

    //CHECK:        [[CST:%.*]] = const.Declare tensor<1x128x16x1xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x1xf16>, [#const.Reorder<#NHWC>]

    //CHECK:        [[CST_INPUT:%.*]] =  VPU.NCE.ClusterTiling ([[CST]] as [[ARG4:%.+]]: tensor<1x128x16x1xf16, {order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x128x16x1xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 128, 9, 1], [1, 128, 9, 1]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 128, 9, 1], [1, 128, 9, 1]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]}>
    //CHECK:            [[RES0:%.*]] = VPU.Copy([[ARG4]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x1xf16, {order = #NHWC}>
    //CHECK-SAME:           -> tensor<1x128x16x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES0]]
    //CHECK:        }

    //CHECK:        [[INPUT_CMX:%.*]] = VPU.NCE.ClusterTiling (%arg0 as [[ARG5:%.+]]: tensor<1x128x16x157xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x128x16x157xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]}>
    //CHECK:            [[RES1:%.*]] = VPU.Copy([[ARG5]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x157xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-SAME:           -> tensor<1x128x16x157xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES1]]
    //CHECK:        }

    //CHECK:        [[CONV_OUTPUT:%.*]] = VPU.NCE.ClusterTiling ([[INPUT_CMX]] as [[ARG6:%.+]]: tensor<1x128x16x157xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg1 as [[ARG7:%.+]]: tensor<128x128x3x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg3 as [[ARG8:%.+]]: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x128x16x157xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 128, 8, 157], [1, 128, 8, 157]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]}>
    //CHECK:            [[RES2:%.*]] = VPU.NCE.Convolution([[ARG6]], [[ARG7]], [[ARG8]])
    //CHECK-SAME:           -> tensor<1x128x16x157xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES2]]
    //CHECK:        }

    //CHECK:        [[CONCAT_OUTPUT:%.*]] = VPU.Concat([[CST_INPUT]], [[CONV_OUTPUT]])
    //CHECK-SAME{LITERAL}:             {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 1]]} :
    //CHECK-SAME:       !VPU.DistributedTensor<1x128x16x1xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 128, 9, 1], [1, 128, 9, 1]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 128, 9, 1], [1, 128, 9, 1]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]}>
    //CHECK-SAME:       !VPU.DistributedTensor<1x128x16x157xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 128, 8, 157], [1, 128, 8, 157]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 128, 9, 157], [1, 128, 9, 157]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x128x16x158xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 128, 9, 158], [1, 128, 9, 158]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 128, 9, 158], [1, 128, 9, 158]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]]}>

    //CHECK:        [[OUTPUT:%.*]] = VPU.NCE.ClusterTiling ([[CONCAT_OUTPUT]] as [[ARG7:%.+]]: tensor<1x128x16x158xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x128x16x158xf16, #NHWC, @CMX_NN
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 128, 8, 158], [1, 128, 8, 158]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 128, 8, 158], [1, 128, 8, 158]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 8, 0]]}>
    //CHECK:            [[RES3:%.*]]  = VPU.NCE.Convolution([[ARG7]]
    //CHECK:            VPU.Yield [[RES3]]
    //CHECK:        }
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConvIn0 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 1, 2],
    num_clusters = 2,
    compute_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    memory_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]
}>

!ConvIn1 = !VPU.DistributedTensor<
    1x16x20x32xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 1, 2],
    num_clusters = 2,
    compute_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    memory_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]
}>

!ConvOut0 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 1, 2],
    num_clusters = 2,
    compute_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    memory_shapes = [[1, 64, 20, 18], [1, 64, 20, 18]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]
}>

!ConvOut1 = !VPU.DistributedTensor<
    1x16x20x32xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 1, 2],
    num_clusters = 2,
    compute_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    memory_shapes = [[1, 16, 20, 18], [1, 16, 20, 18]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]
}>

!ConvIn23 = !VPU.DistributedTensor<
    1x80x12x32xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 1, 2],
    num_clusters = 2,
    compute_shapes = [[1, 80, 12, 18], [1, 80, 12, 18]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]],
    memory_shapes = [[1, 80, 12, 18], [1, 80, 12, 18]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]
}>

!ConvOut23 = !VPU.DistributedTensor<
    1x64x12x32xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 1, 2],
    num_clusters = 2,
    compute_shapes = [[1, 64, 12, 16], [1, 64, 12, 16]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    memory_shapes = [[1, 64, 12, 16], [1, 64, 12, 16]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]
}>

!ConvInOut0_DDR = tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvInOut1_DDR = tensor<1x16x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn23_DDR = tensor<1x80x12x32xf16, {mem_space = @DDR, order = #NHWC}>

!ConvInOutStub0_CMX = tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInOutStub1_CMX = tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub23_CMX = tensor<1x80x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

func.func @SOWProducersSOWConsumersOfConcatWithExplicitDistributedAttrWithHSlice(
        %input0: !ConvInOut0_DDR,
        %input1: !ConvInOut1_DDR,
        %weights0: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights2: tensor<64x80x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights3: tensor<64x80x5x5xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable1: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> (!ConvOut23, !ConvOut23) {

    %input0CMX = VPU.NCE.ClusterTiling(%input0 as %arg1: !ConvInOut0_DDR) -> !ConvIn0 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut0_DDR -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0Output = VPU.NCE.ClusterTiling (
        %input0CMX as %arg2: !ConvInOutStub0_CMX,
        %weights0 as %arg3: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg4: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut0 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [64, 64, 1, 1], strides = [1, 1]} -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0OutDDR = VPU.NCE.ClusterTiling (%conv0Output as %arg5: !ConvInOutStub0_CMX) -> !ConvInOut0_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOutStub0_CMX -> !ConvInOut0_DDR
        VPU.Yield %0
    }

    %input1CMX = VPU.NCE.ClusterTiling(%input1 as %arg1: !ConvInOut1_DDR) -> !ConvIn1 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut1_DDR -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1Output = VPU.NCE.ClusterTiling (
        %input1CMX as %arg2: !ConvInOutStub1_CMX,
        %weights1 as %arg3: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1 as %arg4: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut1 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [16, 16, 1, 1], strides = [1, 1]} -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1OutDDR = VPU.NCE.ClusterTiling (%conv1Output as %arg5: !ConvInOut1_DDR) -> !ConvInOut1_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOut1_DDR -> !ConvInOut1_DDR
        VPU.Yield %0
    }

    %concatOut = VPU.Concat(%conv0OutDDR, %conv1OutDDR) {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
        !ConvInOut0_DDR, !ConvInOut1_DDR -> tensor<1x80x20x32xf16, {mem_space = @DDR, order = #NHWC}>

    %slice0 = VPU.Slice %concatOut [0, 0, 0, 0] [1, 80, 12, 32] : tensor<1x80x20x32xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn23_DDR

    %input2CMX = VPU.NCE.ClusterTiling (%slice0 as %arg6: !ConvIn23_DDR) -> !ConvIn23 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn23_DDR -> !ConvInStub23_CMX
        VPU.Yield %0
    }

    %output0 = VPU.NCE.ClusterTiling (
        %input2CMX as %arg7: !ConvInStub23_CMX,
        %weights2 as %arg8: tensor<64x80x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg9: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 1, right = 1, top = 1, bottom = 1>,
            rawFilterShape = [64, 80, 3, 3], strides = [1, 1]} -> tensor<1x64x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    %slice1 = VPU.Slice %concatOut [0, 0, 8, 0] [1, 80, 12, 32] : tensor<1x80x20x32xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn23_DDR

    %input3CMX = VPU.NCE.ClusterTiling (%slice1 as %arg6: !ConvIn23_DDR) -> !ConvIn23 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn23_DDR -> !ConvInStub23_CMX
        VPU.Yield %0
    }

    %output1 = VPU.NCE.ClusterTiling (
        %input3CMX as %arg7: !ConvInStub23_CMX,
        %weights3 as %arg8: tensor<64x80x5x5xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg9: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 2, right = 2, top = 2, bottom = 2>,
            rawFilterShape = [64, 80, 5, 5], strides = [1, 1]} -> tensor<1x64x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    return %output0, %output1: !ConvOut23, !ConvOut23

    //CHECK:        [[IN0_CMX:%.*]] =  VPU.NCE.ClusterTiling (%arg0 as [[IN0_DDR:%.+]]: tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]}>
    //CHECK:            [[RES0:%.*]] = VPU.Copy([[IN0_DDR]]) {out_mem_space = @CMX_NN} : tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-SAME:           -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES0]]
    //CHECK:        }

    //CHECK:        [[CONV0_OUT:%.*]] = VPU.NCE.ClusterTiling ([[IN0_CMX]] as [[IN0:%.+]]: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg2 as [[W0:%.+]]: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg6 as [[WT0:%.+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 64, 20, 18], [1, 64, 20, 18]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>
    //CHECK:            [[RES1:%.*]] = VPU.NCE.Convolution([[IN0]], [[W0]], [[WT0]])
    //CHECK-SAME:           -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES1]]
    //CHECK:        }

    //CHECK:        [[IN1_CMX:%.*]] = VPU.NCE.ClusterTiling (%arg1 as [[IN1_DDR:%.+]]: tensor<1x16x20x32xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]}>
    //CHECK:            [[RES2:%.*]] = VPU.Copy([[IN1_DDR]]) {out_mem_space = @CMX_NN} : tensor<1x16x20x32xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-SAME:           -> tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES2]]
    //CHECK:        }

    //CHECK:        [[CONV1_OUT:%.*]] = VPU.NCE.ClusterTiling ([[IN1_CMX]] as [[IN1:%.+]]: tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg3 as [[W1:%.+]]: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                %arg7 as [[WT1:%.+]]: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 16, 20, 18], [1, 16, 20, 18]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>
    //CHECK:            [[RES3:%.*]] = VPU.NCE.Convolution([[IN1]], [[W1]], [[WT1]])
    //CHECK-SAME:           -> tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES3]]
    //CHECK:        }

    //CHECK:        [[CONCAT_OUT:%.*]] = VPU.Concat([[CONV0_OUT]], [[CONV1_OUT]])
    //CHECK-SAME{LITERAL}:             {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
    //CHECK-SAME:       !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 20, 16], [1, 64, 20, 16]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 18], [1, 64, 20, 18]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>
    //CHECK-SAME:       !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 16, 20, 16], [1, 16, 20, 16]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 16, 20, 18], [1, 16, 20, 18]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x80x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 80, 20, 18], [1, 80, 20, 18]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 80, 20, 18], [1, 80, 20, 18]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>

    //CHECK: [[SLICE0:%.*]] = VPU.Slice [[CONCAT_OUT]] [0, 0, 0, 0] [1, 80, 12, 32]
    //CHECK-SAME:           to !VPU.DistributedTensor<1x80x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 80, 12, 18], [1, 80, 12, 18]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 80, 12, 18], [1, 80, 12, 18]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>

    //CHECK:        VPU.NCE.ClusterTiling ([[SLICE0]] as [[ARG7:%.+]]: tensor<1x80x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 12, 16], [1, 64, 12, 16]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 12, 16], [1, 64, 12, 16]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]}> {
    //CHECK:            VPU.NCE.Convolution([[ARG7]]

        //CHECK: [[SLICE1:%.*]] = VPU.Slice [[CONCAT_OUT]] [0, 0, 8, 0] [1, 80, 12, 32]
    //CHECK-SAME:           to !VPU.DistributedTensor<1x80x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 80, 12, 18], [1, 80, 12, 18]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 80, 12, 18], [1, 80, 12, 18]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 14]]}>

    //CHECK:        VPU.NCE.ClusterTiling ([[SLICE1]] as [[ARG8:%.+]]: tensor<1x80x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "OVERLAPPED", num_tiles = [1, 1, 1, 2], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 12, 16], [1, 64, 12, 16]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 12, 16], [1, 64, 12, 16]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 16]]}> {
    //CHECK:            VPU.NCE.Convolution([[ARG8]]
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConvIn0 = !VPU.DistributedTensor<
    1x16x8x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 16, 4, 10], [1, 16, 4, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 4, 0]],
    memory_shapes = [[1, 16, 4, 10], [1, 16, 4, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 4, 0]]
}>

!ConvIn1 = !VPU.DistributedTensor<
    1x32x8x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 4, 10], [1, 32, 4, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 4, 0]],
    memory_shapes = [[1, 32, 4, 10], [1, 32, 4, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 4, 0]]
}>

!ConvOut0 = !VPU.DistributedTensor<
    1x16x8x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 16, 4, 10], [1, 16, 4, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 4, 0]],
    memory_shapes = [[1, 16, 5, 10], [1, 16, 5, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!ConvOut1 = !VPU.DistributedTensor<
    1x32x8x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 4, 10], [1, 32, 4, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 4, 0]],
    memory_shapes = [[1, 32, 5, 10], [1, 32, 5, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!ConvIn23 = !VPU.DistributedTensor<
    1x48x4x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 48, 3, 10], [1, 48, 3, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 1, 0]],
    memory_shapes = [[1, 48, 3, 10], [1, 48, 3, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 1, 0]]
}>

!ConvOut23 = !VPU.DistributedTensor<
    1x48x4x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 48, 2, 10], [1, 48, 2, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 2, 0]],
    memory_shapes = [[1, 48, 2, 10], [1, 48, 2, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 2, 0]]
}>

!ConvInOut0_DDR = tensor<1x16x8x10xf16, {mem_space = @DDR, order = #NHWC}>
!ConvInOut1_DDR = tensor<1x32x8x10xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn23_DDR = tensor<1x48x4x10xf16, {mem_space = @DDR, order = #NHWC}>

!ConvInOutStub0_CMX = tensor<1x16x8x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInOutStub1_CMX = tensor<1x32x8x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub23_CMX = tensor<1x48x4x10xf16, {mem_space = @CMX_NN, order = #NHWC}>

func.func @SOHProducersSOHConsumersOfConcatWithExplicitDistributedAttrWithHSlice(
        %input0: !ConvInOut0_DDR,
        %input1: !ConvInOut1_DDR,
        %weights0: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights2: tensor<48x48x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights3: tensor<48x48x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable1: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable2: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> (!ConvOut23, !ConvOut23) {

    %input0CMX = VPU.NCE.ClusterTiling(%input0 as %arg1: !ConvInOut0_DDR) -> !ConvIn0 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut0_DDR -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0Output = VPU.NCE.ClusterTiling (
        %input0CMX as %arg2: !ConvInOutStub0_CMX,
        %weights0 as %arg3: tensor<16x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg4: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut0 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [16, 16, 1, 1], strides = [1, 1]} -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0OutDDR = VPU.NCE.ClusterTiling (%conv0Output as %arg5: !ConvInOutStub0_CMX) -> !ConvInOut0_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOutStub0_CMX -> !ConvInOut0_DDR
        VPU.Yield %0
    }

    %input1CMX = VPU.NCE.ClusterTiling(%input1 as %arg1: !ConvInOut1_DDR) -> !ConvIn1 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut1_DDR -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1Output = VPU.NCE.ClusterTiling (
        %input1CMX as %arg2: !ConvInOutStub1_CMX,
        %weights1 as %arg3: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1 as %arg4: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut1 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [32, 32, 1, 1], strides = [1, 1]} -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1OutDDR = VPU.NCE.ClusterTiling (%conv1Output as %arg5: !ConvInOutStub1_CMX) -> !ConvInOut1_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOutStub1_CMX -> !ConvInOut1_DDR
        VPU.Yield %0
    }

    %concatOut = VPU.Concat(%conv0OutDDR, %conv1OutDDR) {static_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]]} :
        !ConvInOut0_DDR, !ConvInOut1_DDR -> tensor<1x48x8x10xf16, {mem_space = @DDR, order = #NHWC}>

    %slice0 = VPU.Slice %concatOut [0, 0, 0, 0] [1, 48, 4, 10] : tensor<1x48x8x10xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn23_DDR

    %input2CMX = VPU.NCE.ClusterTiling (%slice0 as %arg6: !ConvIn23_DDR) -> !ConvIn23 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn23_DDR -> !ConvInStub23_CMX
        VPU.Yield %0
    }

    %output0 = VPU.NCE.ClusterTiling (
        %input2CMX as %arg7: !ConvInStub23_CMX,
        %weights2 as %arg8: tensor<48x48x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable2 as %arg9: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 1, right = 1, top = 1, bottom = 1>,
            rawFilterShape = [48, 48, 3, 3], strides = [1, 1]} -> tensor<1x48x4x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    %slice1 = VPU.Slice %concatOut [0, 0, 0, 0] [1, 48, 4, 10] : tensor<1x48x8x10xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn23_DDR

    %input3CMX = VPU.NCE.ClusterTiling (%slice1 as %arg6: !ConvIn23_DDR) -> !ConvIn23 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn23_DDR -> !ConvInStub23_CMX
        VPU.Yield %0
    }

    %output1 = VPU.NCE.ClusterTiling (
        %input3CMX as %arg7: !ConvInStub23_CMX,
        %weights3 as %arg8: tensor<48x48x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable2 as %arg9: tensor<48x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [48, 48, 1, 1], strides = [1, 1]} -> tensor<1x48x4x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    return %output0, %output1: !ConvOut23, !ConvOut23
}

// CHECK:               VPU.Concat
// CHECK-SAME{LITERAL}:   {static_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]]}
// CHECK-SAME:              : tensor<1x16x8x10xf16, {mem_space = @DDR, order = #NHWC}>, tensor<1x32x8x10xf16, {mem_space = @DDR, order = #NHWC}>
// CHECK-SAME:              -> tensor<1x48x8x10xf16, {mem_space = @DDR, order = #NHWC}>

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConvIn01 = !VPU.DistributedTensor<
    1x16x10x10xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 16, 10, 10], [1, 16, 10, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 16, 10, 10], [1, 16, 10, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut0 = !VPU.DistributedTensor<
    1x32x10x10xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 16, 10, 10], [1, 16, 10, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    memory_shapes = [[1, 32, 10, 10], [1, 32, 10, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut1 = !VPU.DistributedTensor<
    1x64x10x10xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 10, 10], [1, 32, 10, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    memory_shapes = [[1, 64, 10, 10], [1, 64, 10, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvIn2 = !VPU.DistributedTensor<
    1x96x5x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 96, 3, 10], [1, 96, 2, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    memory_shapes = [[1, 96, 3, 10], [1, 96, 2, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!ConvIn3 = !VPU.DistributedTensor<
    1x96x6x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 96, 3, 10], [1, 96, 3, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    memory_shapes = [[1, 96, 3, 10], [1, 96, 3, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!ConvOut2 = !VPU.DistributedTensor<
    1x96x5x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 96, 3, 10], [1, 96, 2, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    memory_shapes = [[1, 96, 3, 10], [1, 96, 2, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!ConvOut3 = !VPU.DistributedTensor<
    1x96x6x10xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 96, 3, 10], [1, 96, 3, 10]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    memory_shapes = [[1, 96, 3, 10], [1, 96, 3, 10]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!ConvIn01_DDR = tensor<1x16x10x10xf16, {mem_space = @DDR, order = #NHWC}>
!ConvOut0_DDR = tensor<1x32x10x10xf16, {mem_space = @DDR, order = #NHWC}>
!ConvOut1_DDR = tensor<1x64x10x10xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn2_DDR = tensor<1x96x5x10xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn3_DDR = tensor<1x96x6x10xf16, {mem_space = @DDR, order = #NHWC}>

!ConvInStub01_CMX = tensor<1x16x10x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvOutStub0_CMX = tensor<1x32x10x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvOutStub1_CMX = tensor<1x64x10x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub2_CMX = tensor<1x96x5x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub3_CMX = tensor<1x96x6x10xf16, {mem_space = @CMX_NN, order = #NHWC}>

func.func @SOKProducersSOHConsumersOfConcatWithExplicitDistributedAttrWithHSlice(
        %input: !ConvIn01_DDR,
        %weights0: tensor<32x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1: tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights2: tensor<96x96x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable1: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable2: tensor<96x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> (!ConvOut2, !ConvOut3) {

    %inputCMX = VPU.NCE.ClusterTiling(%input as %arg1: !ConvIn01_DDR) -> !ConvIn01 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvIn01_DDR -> !ConvInStub01_CMX
        VPU.Yield %0
    }

    %conv0Output = VPU.NCE.ClusterTiling (
        %inputCMX as %arg2: !ConvInStub01_CMX,
        %weights0 as %arg3: tensor<32x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg4: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut0 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [32, 16, 1, 1], strides = [1, 1]} -> !ConvOutStub0_CMX
        VPU.Yield %0
    }

    %conv0OutDDR = VPU.NCE.ClusterTiling (%conv0Output as %arg5: !ConvOutStub0_CMX) -> !ConvOut0_DDR {
        %0 = VPU.Copy(%arg5) : !ConvOutStub0_CMX -> !ConvOut0_DDR
        VPU.Yield %0
    }

    %conv1Output = VPU.NCE.ClusterTiling (
        %inputCMX as %arg2: !ConvInStub01_CMX,
        %weights1 as %arg3: tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1 as %arg4: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut1 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [64, 16, 1, 1], strides = [1, 1]} -> !ConvOutStub1_CMX
        VPU.Yield %0
    }

    %conv1OutDDR = VPU.NCE.ClusterTiling (%conv1Output as %arg5: !ConvOutStub1_CMX) -> !ConvOut1_DDR {
        %0 = VPU.Copy(%arg5) : !ConvOutStub1_CMX -> !ConvOut1_DDR
        VPU.Yield %0
    }

    %concatOut = VPU.Concat(%conv0OutDDR, %conv1OutDDR) {static_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]]} :
        !ConvOut0_DDR, !ConvOut1_DDR -> tensor<1x96x10x10xf16, {mem_space = @DDR, order = #NHWC}>

    %slice0 = VPU.Slice %concatOut [0, 0, 0, 0] [1, 96, 5, 10] : tensor<1x96x10x10xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn2_DDR

    %input2CMX = VPU.NCE.ClusterTiling (%slice0 as %arg6: !ConvIn2_DDR) -> !ConvIn2 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn2_DDR -> !ConvInStub2_CMX
        VPU.Yield %0
    }

    %output0 = VPU.NCE.ClusterTiling (
        %input2CMX as %arg7: !ConvInStub2_CMX,
        %weights2 as %arg8: tensor<96x96x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable2 as %arg9: tensor<96x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut2 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [96, 96, 1, 1], strides = [1, 1]} -> tensor<1x96x5x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    %slice1 = VPU.Slice %concatOut [0, 0, 4, 0] [1, 96, 6, 10] : tensor<1x96x10x10xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn3_DDR

    %input3CMX = VPU.NCE.ClusterTiling (%slice1 as %arg6: !ConvIn3_DDR) -> !ConvIn3 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn3_DDR -> !ConvInStub3_CMX
        VPU.Yield %0
    }

    %output1 = VPU.NCE.ClusterTiling (
        %input3CMX as %arg7: !ConvInStub3_CMX,
        %weights2 as %arg8: tensor<96x96x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable2 as %arg9: tensor<96x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut3 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [96, 96, 1, 1], strides = [1, 1]} -> tensor<1x96x6x10xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    return %output0, %output1: !ConvOut2, !ConvOut3

    // CHECK:               VPU.Concat
    // CHECK-SAME{LITERAL}:   {static_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]]}
    // CHECK-SAME:              : tensor<1x32x10x10xf16, {mem_space = @DDR, order = #NHWC}>, tensor<1x64x10x10xf16, {mem_space = @DDR, order = #NHWC}>
    // CHECK-SAME:              -> tensor<1x96x10x10xf16, {mem_space = @DDR, order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!WeightsType = tensor<
    128x256x3x3xf16,
    {mem_space = @CMX_NN, order = #NHWC}
>

!WeightsTableType = tensor<
    128x1x1x4xsi32,
    {mem_space = @CMX_NN, order = #NCHW}
>

!InDataDistribution = !VPU.DistributedTensor<
    1x256x28x28xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]],
    memory_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]]
}>

!InSparseMapDistribution = !VPU.DistributedTensor<
    1x256x28x28xi1, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]],
    memory_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]]
}>

!OutDataDistribution = !VPU.DistributedTensor<
    1x128x14x14xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 7, 14], [1, 128, 7, 14]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    memory_shapes = [[1, 128, 9, 14], [1, 128, 8, 14]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]
}>

!OutSparseMapDistribution = !VPU.DistributedTensor<
    1x128x14x14xi1, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 7, 14], [1, 128, 7, 14]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    memory_shapes = [[1, 128, 9, 14], [1, 128, 8, 14]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]
}>

!SparseDistributedInput = !VPU.SparseTensor<data=!InDataDistribution, sparsity_map=!InSparseMapDistribution>

!SparseDistributedOutput = !VPU.SparseTensor<data=!OutDataDistribution, sparsity_map=!OutSparseMapDistribution>

!SparseConvInput = !VPU.SparseTensor<
    data=tensor<1x256x28x28xf16, {order = #NHWC}>,
    sparsity_map=tensor<1x256x28x28xi1, {order = #NHWC}>
>

!SparseConvOutput = !VPU.SparseTensor<
    data=tensor<1x128x14x14xf16, {order = #NHWC}>,
    sparsity_map=tensor<1x128x14x14xi1, {order = #NHWC}>
>

!SparseConvInputCMX = !VPU.SparseTensor<
    data=tensor<1x256x28x28xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    sparsity_map=tensor<1x256x28x28xi1, {mem_space = @CMX_NN, order = #NHWC}>
>

!SparseConvOutputCMX = !VPU.SparseTensor<
    data=tensor<1x128x14x14xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    sparsity_map=tensor<1x128x14x14xi1, {mem_space = @CMX_NN, order = #NHWC}>
>

!ConcatOutDataDistribution = !VPU.DistributedTensor<
    1x256x14x14xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]],
    memory_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]
}>

!ConcatOutSparseMapDistribution = !VPU.DistributedTensor<
    1x256x14x14xi1, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]],
    memory_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]
}>

!SparseConcatOutputDist = !VPU.SparseTensor<data=!ConcatOutDataDistribution,sparsity_map=!ConcatOutSparseMapDistribution>

!SparseConcatOutput = !VPU.SparseTensor<
    data=tensor<1x256x14x14xf16, {order = #NHWC}>,
    sparsity_map=tensor<1x256x14x14xi1, {order = #NHWC}>
>

!SparseConcatOutputCMX = !VPU.SparseTensor<
    data=tensor<1x256x14x14xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    sparsity_map=tensor<1x256x14x14xi1, {mem_space = @CMX_NN, order = #NHWC}>
>

!Conv2OutDataDistribution = !VPU.DistributedTensor<
    1x128x6x6xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    memory_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!Conv2OutSparseMapDistribution = !VPU.DistributedTensor<
    1x128x6x6xi1, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2,
    compute_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    memory_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
}>

!SparseConv2OutDist = !VPU.SparseTensor<data=!Conv2OutDataDistribution, sparsity_map=!Conv2OutSparseMapDistribution>

!SparseConv2OutCMX = !VPU.SparseTensor<
    data=tensor<1x128x6x6xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    sparsity_map=tensor<1x128x6x6xi1, {mem_space = @CMX_NN, order = #NHWC}>
>

!SparseConv2OutDDR = !VPU.SparseTensor<
    data=tensor<1x128x6x6xf16, {order = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>}>,
    sparsity_map=tensor<1x128x6x6xi1, {order = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>}>
>

// CHECK:      func.func @SparseConvolution([[INPUT:%.+]]: !VPU.SparseTensor<data=tensor<1x256x28x28xf16, {order = #NHWC}>, sparsity_map=tensor<1x256x28x28xi1, {order = #NHWC}>>,
// CHECK-SAME:                         [[WEIGHTS_TABLE:%.+]]: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
// CHECK-SAME:                         [[WEIGHTS:%.+]]: tensor<128x256x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>)
// CHECK-SAME:         -> !VPU.SparseTensor<data=tensor<1x128x6x6xf16, {order = #NHWC}>, sparsity_map=tensor<1x128x6x6xi1, {order = #NHWC}>> {
func.func @SparseConvolution(%input: !SparseConvInput,
                             %weightsTable: !WeightsTableType,
                             %weights: !WeightsType)
        -> !SparseConv2OutDDR {
    // Convolution 0 in copy
    %0 = VPU.NCE.ClusterTiling (%input as %arg1: !SparseConvInput) -> !SparseDistributedInput {
            %20 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : !SparseConvInput -> !SparseConvInputCMX
        VPU.Yield %20
    }

    // Convolution 0
    %1 = VPU.NCE.ClusterTiling (
        %0 as %arg1: !SparseConvInputCMX,
        %weights as %arg2: !WeightsType,
        %weightsTable as %arg3: !WeightsTableType) -> !SparseDistributedOutput {
        %20 = VPU.NCE.Convolution(%arg1, %arg2, %arg3) {
            pad = #VPU.Padding<left = 1 : i64, right = 0 : i64, top = 1 : i64, bottom = 0 : i64>,
            ppe = #VPU.PPETask<mode = <LRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
            rawFilterShape = [128, 256, 3, 3], strides = [2, 2]}
                -> !SparseConvOutputCMX
        VPU.Yield %20
    }

    // Convolution 0 output copy
    %2 = VPU.NCE.ClusterTiling (%1 as %arg1: !SparseConvOutputCMX) -> !SparseConvOutput {
            %20 = VPU.Copy(%arg1) : !SparseConvOutputCMX -> !SparseConvOutput
        VPU.Yield %20
    }

    // Convolution 1
    %3 = VPU.NCE.ClusterTiling (
        %0 as %arg1: !SparseConvInputCMX,
        %weights as %arg2: !WeightsType,
        %weightsTable as %arg3: !WeightsTableType)  -> !SparseDistributedOutput {
        %20 = VPU.NCE.Convolution(%arg1, %arg2, %arg3) {
            pad = #VPU.Padding<left = 1 : i64, right = 0 : i64, top = 1 : i64, bottom = 0 : i64>,
            ppe = #VPU.PPETask<mode = <LRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
            rawFilterShape = [128, 256, 3, 3], strides = [2, 2]}
                -> !SparseConvOutputCMX
        VPU.Yield %20
    }

    // Convolution 1 output copy
    %4 = VPU.NCE.ClusterTiling (%3 as %arg1: !SparseConvOutputCMX) -> !SparseConvOutput {
            %20 = VPU.Copy(%arg1) : !SparseConvOutputCMX -> !SparseConvOutput
        VPU.Yield %20
    }

    // Concat
    %5 = VPU.Concat(%2, %4) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : !SparseConvOutput, !SparseConvOutput -> !SparseConcatOutput

    // Concat output copy
    %6 = VPU.NCE.ClusterTiling (%5 as %arg1: !SparseConcatOutput) -> !SparseConcatOutputDist {
        %20 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : !SparseConcatOutput -> !SparseConcatOutputCMX
        VPU.Yield %20
    }

    // Convolution 2
    %7 = VPU.NCE.ClusterTiling (
        %6 as %arg1: !SparseConcatOutputCMX,
        %weights as %arg2: !WeightsType,
        %weightsTable as %arg3: !WeightsTableType)
            -> !SparseConv2OutDist {
        %20 = VPU.NCE.Convolution(%arg1, %arg2, %arg3){
            pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
            ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64, lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
            rawFilterShape = [128, 256, 3, 3], strides = [2, 2]} -> !SparseConv2OutCMX
        VPU.Yield %20
    }
    %8 = VPU.NCE.ClusterTiling (%7 as %arg1: !SparseConv2OutCMX) -> !SparseConv2OutDDR {
        %20 = VPU.Copy(%arg1) : !SparseConv2OutCMX -> !SparseConv2OutDDR
        VPU.Yield %20
    }

    return %8 : !SparseConv2OutDDR

    // Copy DDR -> CMX
    // CHECK:       [[IN_CMX:%.+]] = VPU.NCE.ClusterTiling ([[INPUT]] as [[INNER_ARG0:[^:]+]]:
    // CHECK-SAME:      !VPU.SparseTensor<data=tensor<1x256x28x28xf16, {order = #NHWC}>,
    // CHECK-SAME:                        sparsity_map=tensor<1x256x28x28xi1, {order = #NHWC}>>
    // CHECK-SAME:      -> !VPU.SparseTensor<
    // CHECK-SAME:              data=!VPU.DistributedTensor<1x256x28x28xf16, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]]}>
    // CHECK-SAME:              sparsity_map=!VPU.DistributedTensor<1x256x28x28xi1, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 256, 16, 28], [1, 256, 15, 28]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 13, 0]]}>
    // CHECK:           VPU.Copy([[INNER_ARG0]])

    // Convolution 0
    // CHECK:       [[CONV0:%.+]] = VPU.NCE.ClusterTiling ([[IN_CMX]] as [[INNER_ARG0:[^:]+]]:
    // CHECK-SAME:      !VPU.SparseTensor<data=tensor<1x256x28x28xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                        sparsity_map=tensor<1x256x28x28xi1, {mem_space = @CMX_NN, order = #NHWC}>>,
    // CHECK-SAME:                                         [[WEIGHTS]] as [[INNER_ARG1:[^:]+]]: tensor<128x256x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                                         [[WEIGHTS_TABLE]] as [[INNER_ARG2:[^:]+]]: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:      -> !VPU.SparseTensor<
    // CHECK-SAME:              data=!VPU.DistributedTensor<1x128x14x14xf16, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 128, 7, 14], [1, 128, 7, 14]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 128, 9, 14], [1, 128, 8, 14]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]}>
    // CHECK-SAME:              sparsity_map=!VPU.DistributedTensor<1x128x14x14xi1, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 128, 7, 14], [1, 128, 7, 14]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 128, 9, 14], [1, 128, 8, 14]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]}>
    // CHECK:           VPU.NCE.Convolution([[INNER_ARG0]], [[INNER_ARG1]], [[INNER_ARG2]])

    // Convolution 1
    // CHECK:       [[CONV1:%.+]] = VPU.NCE.ClusterTiling ([[IN_CMX]] as [[INNER_ARG3:[^:]+]]:
    // CHECK-SAME:      !VPU.SparseTensor<data=tensor<1x256x28x28xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                        sparsity_map=tensor<1x256x28x28xi1, {mem_space = @CMX_NN, order = #NHWC}>>,
    // CHECK-SAME:                                         [[WEIGHTS]] as [[INNER_ARG4:[^:]+]]: tensor<128x256x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                                         [[WEIGHTS_TABLE]] as [[INNER_ARG5:[^:]+]]: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:      -> !VPU.SparseTensor<
    // CHECK-SAME:              data=!VPU.DistributedTensor<1x128x14x14xf16, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 128, 7, 14], [1, 128, 7, 14]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 128, 9, 14], [1, 128, 8, 14]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]}>
    // CHECK-SAME:              sparsity_map=!VPU.DistributedTensor<1x128x14x14xi1, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 128, 7, 14], [1, 128, 7, 14]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 7, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 128, 9, 14], [1, 128, 8, 14]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]}>
    // CHECK:           VPU.NCE.Convolution([[INNER_ARG3]], [[INNER_ARG4]], [[INNER_ARG5]])

    // Concat
    // CHECK:       [[CONCAT_CMX:%.+]] = VPU.Concat([[CONV0]], [[CONV1]])
    // CHECK-SAME:      -> !VPU.SparseTensor<
    // CHECK-SAME:              data=!VPU.DistributedTensor<1x256x14x14xf16, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64,
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]}>
    // CHECK-SAME:              sparsity_map=!VPU.DistributedTensor<1x256x14x14xi1, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 256, 9, 14], [1, 256, 8, 14]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 6, 0]]}>

    // Convolution 2
    // CHECK:       [[CONV2:%.+]] = VPU.NCE.ClusterTiling ([[CONCAT_CMX]] as [[INNER_ARG6:[^:]+]]:
    // CHECK-SAME:      !VPU.SparseTensor<data=tensor<1x256x14x14xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                        sparsity_map=tensor<1x256x14x14xi1, {mem_space = @CMX_NN, order = #NHWC}>>,
    // CHECK-SAME:                                         [[WEIGHTS]] as [[INNER_ARG7:[^:]+]]: tensor<128x256x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                                         [[WEIGHTS_TABLE]] as [[INNER_ARG8:[^:]+]]: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:      -> !VPU.SparseTensor<
    // CHECK-SAME:              data=!VPU.DistributedTensor<1x128x6x6xf16, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
    // CHECK-SAME:              sparsity_map=!VPU.DistributedTensor<1x128x6x6xi1, #NHWC, @CMX_NN,
    // CHECK-SAME:                    {mode = "OVERLAPPED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64
    // CHECK-SAME{LITERAL}:            compute_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    // CHECK-SAME{LITERAL}:            compute_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]],
    // CHECK-SAME{LITERAL}:            memory_shapes = [[1, 128, 3, 6], [1, 128, 3, 6]],
    // CHECK-SAME{LITERAL}:            memory_offsets = [[0, 0, 0, 0], [0, 0, 3, 0]]
    // CHECK:           VPU.NCE.Convolution([[INNER_ARG6]], [[INNER_ARG7]], [[INNER_ARG8]])

}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConvIn0 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvIn1 = !VPU.DistributedTensor<
    1x32x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut0 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut1 = !VPU.DistributedTensor<
    1x32x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvIn23 = !VPU.DistributedTensor<
    1x96x12x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 96, 12, 32], [1, 96, 12, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 96, 12, 32], [1, 96, 12, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut23 = !VPU.DistributedTensor<
    1x64x12x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 12, 32], [1, 32, 12, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    memory_shapes = [[1, 64, 12, 32], [1, 64, 12, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvInOut0_DDR = tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvInOut1_DDR = tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn23_DDR = tensor<1x96x12x32xf16, {mem_space = @DDR, order = #NHWC}>

!ConvInOutStub0_CMX = tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInOutStub1_CMX = tensor<1x32x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub23_CMX = tensor<1x96x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK-LABEL: @SOKProducersSOKConsumersOfConcatWithExplicitDistributedAttrWithHSlice
// CHECK-SAME: ([[FUNC_IN0:%.+]]: tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
// CHECK-SAME:  [[FUNC_IN1:%.+]]: tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>
// CHECK-SAME:  [[W0:%.+]]: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[W1:%.+]]: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[W2:%.+]]: tensor<64x96x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[W3:%.+]]: tensor<64x96x5x5xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[WT0:%.+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
// CHECK-SAME:  [[WT1:%.+]]: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
func.func @SOKProducersSOKConsumersOfConcatWithExplicitDistributedAttrWithHSlice(
        %input0: !ConvInOut0_DDR,
        %input1: !ConvInOut1_DDR,
        %weights0: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights2: tensor<64x96x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights3: tensor<64x96x5x5xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable1: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> (!ConvOut23, !ConvOut23) {

    %input0CMX = VPU.NCE.ClusterTiling(%input0 as %arg1: !ConvInOut0_DDR) -> !ConvIn0 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut0_DDR -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0Output = VPU.NCE.ClusterTiling (
        %input0CMX as %arg2: !ConvInOutStub0_CMX,
        %weights0 as %arg3: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg4: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut0 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [64, 64, 1, 1], strides = [1, 1]} -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0OutDDR = VPU.NCE.ClusterTiling (%conv0Output as %arg5: !ConvInOutStub0_CMX) -> !ConvInOut0_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOutStub0_CMX -> !ConvInOut0_DDR
        VPU.Yield %0
    }

    %input1CMX = VPU.NCE.ClusterTiling(%input1 as %arg1: !ConvInOut1_DDR) -> !ConvIn1 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut1_DDR -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1Output = VPU.NCE.ClusterTiling (
        %input1CMX as %arg2: !ConvInOutStub1_CMX,
        %weights1 as %arg3: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1 as %arg4: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut1 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [32, 32, 1, 1], strides = [1, 1]} -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1OutDDR = VPU.NCE.ClusterTiling (%conv1Output as %arg5: !ConvInOut1_DDR) -> !ConvInOut1_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOut1_DDR -> !ConvInOut1_DDR
        VPU.Yield %0
    }

    %concatOut = VPU.Concat(%conv0OutDDR, %conv1OutDDR) {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
        !ConvInOut0_DDR, !ConvInOut1_DDR -> tensor<1x96x20x32xf16, {mem_space = @DDR, order = #NHWC}>

    %slice0 = VPU.Slice %concatOut [0, 0, 0, 0] [1, 96, 12, 32] : tensor<1x96x20x32xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn23_DDR

    %input2CMX = VPU.NCE.ClusterTiling (%slice0 as %arg6: !ConvIn23_DDR) -> !ConvIn23 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn23_DDR -> !ConvInStub23_CMX
        VPU.Yield %0
    }

    %output0 = VPU.NCE.ClusterTiling (
        %input2CMX as %arg7: !ConvInStub23_CMX,
        %weights2 as %arg8: tensor<64x96x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg9: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 1, right = 1, top = 1, bottom = 1>,
            rawFilterShape = [64, 96, 3, 3], strides = [1, 1]} -> tensor<1x64x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    %slice1 = VPU.Slice %concatOut [0, 0, 8, 0] [1, 96, 12, 32] : tensor<1x96x20x32xf16, {mem_space = @DDR, order = #NHWC}> to !ConvIn23_DDR

    %input3CMX = VPU.NCE.ClusterTiling (%slice1 as %arg6: !ConvIn23_DDR) -> !ConvIn23 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn23_DDR -> !ConvInStub23_CMX
        VPU.Yield %0
    }

    %output1 = VPU.NCE.ClusterTiling (
        %input3CMX as %arg7: !ConvInStub23_CMX,
        %weights3 as %arg8: tensor<64x96x5x5xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg9: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 2, right = 2, top = 2, bottom = 2>,
            rawFilterShape = [64, 96, 5, 5], strides = [1, 1]} -> tensor<1x64x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    return %output0, %output1: !ConvOut23, !ConvOut23

    //CHECK:        [[IN0_CMX:%.*]] =  VPU.NCE.ClusterTiling ([[FUNC_IN0]] as [[IN0_DDR:%.+]]: tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK:            [[RES0:%.*]] = VPU.Copy([[IN0_DDR]]) {out_mem_space = @CMX_NN} : tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-SAME:           -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES0]]
    //CHECK:        }

    //CHECK:        [[CONV0_OUT:%.*]] = VPU.NCE.ClusterTiling ([[IN0_CMX]] as [[IN0:%.+]]: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[W0]] as [[INNER_W0:%.+]]: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[WT0]] as [[INNER_WT0:%.+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK:            [[RES1:%.*]] = VPU.NCE.Convolution([[IN0]], [[INNER_W0]], [[INNER_WT0]])
    //CHECK-SAME:           -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES1]]
    //CHECK:        }

    //CHECK:        [[IN1_CMX:%.*]] = VPU.NCE.ClusterTiling ([[FUNC_IN1]] as [[IN1_DDR:%.+]]: tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK:            [[RES2:%.*]] = VPU.Copy([[IN1_DDR]]) {out_mem_space = @CMX_NN} : tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-SAME:           -> tensor<1x32x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES2]]
    //CHECK:        }

    //CHECK:        [[CONV1_OUT:%.*]] = VPU.NCE.ClusterTiling ([[IN1_CMX]] as [[IN1:%.+]]: tensor<1x32x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[W1]] as [[INNER_W1:%.+]]: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[WT1]] as [[INNER_WT1:%.+]]: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK:            [[RES3:%.*]] = VPU.NCE.Convolution([[IN1]], [[INNER_W1]], [[INNER_WT1]])
    //CHECK-SAME:           -> tensor<1x32x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK:            VPU.Yield [[RES3]]
    //CHECK:        }

    //CHECK:        [[D_CAST0:%.*]] = VPU.DistributedCast([[CONV0_OUT]] :
    //CHECK-SAME:          !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:          -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                 {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:         compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:         compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:         memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:         memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        [[D_CAST1:%.*]] = VPU.DistributedCast([[CONV1_OUT]] :
    //CHECK-SAME:          !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:          -> !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                 {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:         compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:         compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:         memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:         memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        [[CONCAT_OUT:%.*]] = VPU.Concat([[D_CAST0]], [[D_CAST1]])
    //CHECK-SAME{LITERAL}:             {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
    //CHECK-SAME:       !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:       !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x96x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 96, 20, 32], [1, 96, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 96, 20, 32], [1, 96, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK: [[SLICE0:%.*]] = VPU.Slice [[CONCAT_OUT]] [0, 0, 0, 0] [1, 96, 12, 32]
    //CHECK-SAME:           to !VPU.DistributedTensor<1x96x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 96, 12, 32], [1, 96, 12, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 96, 12, 32], [1, 96, 12, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        VPU.NCE.ClusterTiling ([[SLICE0]] as [[ARG7:%.+]]: tensor<1x96x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 12, 32], [1, 32, 12, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 12, 32], [1, 64, 12, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}> {
    //CHECK:            VPU.NCE.Convolution([[ARG7]]

    //CHECK: [[SLICE1:%.*]] = VPU.Slice [[CONCAT_OUT]] [0, 0, 8, 0] [1, 96, 12, 32]
    //CHECK-SAME:           to !VPU.DistributedTensor<1x96x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 96, 12, 32], [1, 96, 12, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 96, 12, 32], [1, 96, 12, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        VPU.NCE.ClusterTiling ([[SLICE1]] as [[ARG8:%.+]]: tensor<1x96x12x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x12x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 12, 32], [1, 32, 12, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 12, 32], [1, 64, 12, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}> {
    //CHECK:            VPU.NCE.Convolution([[ARG8]]
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!ConvIn0 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvIn1 = !VPU.DistributedTensor<
    1x32x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut0 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut1 = !VPU.DistributedTensor<
    1x32x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvIn2 = !VPU.DistributedTensor<
    1x96x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 96, 20, 32], [1, 96, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 96, 20, 32], [1, 96, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvOut23 = !VPU.DistributedTensor<
    1x64x20x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED|DUPLICATED",
    num_tiles = [1, 2, 1, 1],
    num_clusters = 2,
    compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!InterpIn = !VPU.DistributedTensor<
    1x16x10x16xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 16, 10, 16], [1, 16, 10, 16]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 16, 10, 16], [1, 16, 10, 16]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!InterpOut = !VPU.DistributedTensor<
    1x16x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvIn3 = !VPU.DistributedTensor<
    1x80x20x32xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 2,
    compute_shapes = [[1, 80, 20, 32], [1, 80, 20, 32]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[1, 80, 20, 32], [1, 80, 20, 32]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]
}>

!ConvInOut0_DDR = tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvInOut1_DDR = tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!InterpIn_DDR = tensor<1x16x10x16xf16, {mem_space = @DDR, order = #NHWC}>
!InterpOut_DDR = tensor<1x16x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn2_DDR = tensor<1x96x20x32xf16, {mem_space = @DDR, order = #NHWC}>
!ConvIn3_DDR = tensor<1x80x20x32xf16, {mem_space = @DDR, order = #NHWC}>

!ConvInOutStub0_CMX = tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInOutStub1_CMX = tensor<1x32x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub2_CMX = tensor<1x96x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!ConvInStub3_CMX = tensor<1x80x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!InterpInStub_CMX = tensor<1x16x10x16xf16, {mem_space = @CMX_NN, order = #NHWC}>
!InterpOutStub_CMX = tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK-LABEL: @ComplexConcatWithExplicitDistribution
// CHECK-SAME: ([[FUNC_IN0:%.+]]: tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
// CHECK-SAME:  [[FUNC_IN1:%.+]]: tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>
// CHECK-SAME:  [[FUNC_IN2:%.+]]: tensor<1x16x10x16xf16, {mem_space = @DDR, order = #NHWC}>
// CHECK-SAME:  [[W0:%.+]]: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[W1:%.+]]: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[W2:%.+]]: tensor<64x96x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[W3:%.+]]: tensor<64x80x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>
// CHECK-SAME:  [[WT0:%.+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
// CHECK-SAME:  [[WT1:%.+]]: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
func.func @ComplexConcatWithExplicitDistribution(
        %input0: !ConvInOut0_DDR,
        %input1: !ConvInOut1_DDR,
        %input2: !InterpIn_DDR,
        %weights0: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights1: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights2: tensor<64x96x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weights3: tensor<64x80x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %weightsTable1: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
           -> (!ConvOut23, !ConvOut23) {

    %input0CMX = VPU.NCE.ClusterTiling(%input0 as %arg1: !ConvInOut0_DDR) -> !ConvIn0 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut0_DDR -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0Output = VPU.NCE.ClusterTiling (
        %input0CMX as %arg2: !ConvInOutStub0_CMX,
        %weights0 as %arg3: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg4: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut0 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [64, 64, 1, 1], strides = [1, 1]} -> !ConvInOutStub0_CMX
        VPU.Yield %0
    }

    %conv0OutDDR = VPU.NCE.ClusterTiling (%conv0Output as %arg5: !ConvInOutStub0_CMX) -> !ConvInOut0_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOutStub0_CMX -> !ConvInOut0_DDR
        VPU.Yield %0
    }

    %input1CMX = VPU.NCE.ClusterTiling(%input1 as %arg1: !ConvInOut1_DDR) -> !ConvIn1 {
        %0 = VPU.Copy(%arg1) { out_mem_space = @CMX_NN } : !ConvInOut1_DDR -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1Output = VPU.NCE.ClusterTiling (
        %input1CMX as %arg2: !ConvInOutStub1_CMX,
        %weights1 as %arg3: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable1 as %arg4: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut1 {

        %0 = VPU.NCE.Convolution(%arg2, %arg3, %arg4) {
            pad = #VPU.Padding<left = 0, right = 0, top = 0, bottom = 0>,
            rawFilterShape = [32, 32, 1, 1], strides = [1, 1]} -> !ConvInOutStub1_CMX
        VPU.Yield %0
    }

    %conv1OutDDR = VPU.NCE.ClusterTiling (%conv1Output as %arg5: !ConvInOutStub1_CMX) -> !ConvInOut1_DDR {
        %0 = VPU.Copy(%arg5) : !ConvInOutStub1_CMX -> !ConvInOut1_DDR
        VPU.Yield %0
    }

    %concatOut0 = VPU.Concat(%conv0OutDDR, %conv1OutDDR) {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
        !ConvInOut0_DDR, !ConvInOut1_DDR -> tensor<1x96x20x32xf16, {mem_space = @DDR, order = #NHWC}>


    %input2CMX = VPU.NCE.ClusterTiling (%concatOut0 as %arg6: !ConvIn2_DDR) -> !ConvIn2 {
        %0 = VPU.Copy(%arg6) {out_mem_space = @CMX_NN} : !ConvIn2_DDR -> !ConvInStub2_CMX
        VPU.Yield %0
    }

    %output0 = VPU.NCE.ClusterTiling (
        %input2CMX as %arg7: !ConvInStub2_CMX,
        %weights2 as %arg8: tensor<64x96x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg9: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg7, %arg8, %arg9) {
            pad = #VPU.Padding<left = 1, right = 1, top = 1, bottom = 1>,
            rawFilterShape = [64, 96, 3, 3], strides = [1, 1]} -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }

    %interpInCMX = VPU.NCE.ClusterTiling(%input2 as %arg10: !InterpIn_DDR) -> !InterpIn {
        %0 = VPU.Copy(%arg10) { out_mem_space = @CMX_NN } : !InterpIn_DDR -> !InterpInStub_CMX
        VPU.Yield %0
    }

    %outInterp = VPU.NCE.ClusterTiling (%interpInCMX as %arg11: !InterpInStub_CMX)
        -> !InterpOut {

        %0 = VPU.Interpolate(%arg11) {
            attr = #IE.Interpolate<mode = <NEAREST>,
            shape_calc_mode = <SIZES>,
            coord_mode = <TF_HALF_PIXEL_FOR_NN>,
            nearest_mode = <FLOOR>, antialias = false,
            pads_begin = [0, 0, 0, 0],
            pads_end = [0, 0, 0, 0],
            cube_coeff = -7.500000e-01 : f64>,
            axes_attr = [2, 3],
            initial_input_dims_attr = [1, 16, 10, 16],
            initial_output_dims_attr = [1, 16, 20, 32],
            operandSegmentSizes = array<i32: 1, 0, 0, 0, 0, 0>,
            scales_attr = [2.000000e+00, 2.000000e+00],
            sizes_attr = [20, 32],
            tile_offset_attr = [0.000000e+00, 0.000000e+00, 0.000000e+00, 0.000000e+00]}
             : !InterpInStub_CMX -> !InterpOutStub_CMX
        VPU.Yield %0
    }

    %interpOutDDR = VPU.NCE.ClusterTiling (%outInterp as %arg5: !InterpOutStub_CMX) -> !InterpOut_DDR {
        %0 = VPU.Copy(%arg5) : !InterpOutStub_CMX -> !InterpOut_DDR
        VPU.Yield %0
    }

    %concatOut1 = VPU.Concat(%conv0OutDDR, %interpOutDDR) {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
        !ConvInOut0_DDR, !InterpOut_DDR -> !ConvIn3_DDR

    %input3CMX = VPU.NCE.ClusterTiling (%concatOut1 as %arg12: !ConvIn3_DDR) -> !ConvIn3 {
        %0 = VPU.Copy(%arg12) {out_mem_space = @CMX_NN} : !ConvIn3_DDR -> !ConvInStub3_CMX
        VPU.Yield %0
    }

    %output1 = VPU.NCE.ClusterTiling (
        %input3CMX as %arg13: !ConvInStub3_CMX,
        %weights3 as %arg14: tensor<64x80x3x3xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %weightsTable0 as %arg15: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
        -> !ConvOut23 {

        %0 = VPU.NCE.Convolution(%arg13, %arg14, %arg15) {
            pad = #VPU.Padding<left = 1, right = 1, top = 1, bottom = 1>,
            rawFilterShape = [64, 80, 3, 3], strides = [1, 1]} -> tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %0
    }


    return %output0, %output1: !ConvOut23, !ConvOut23

    //CHECK:        [[IN0_CMX:%.*]] =  VPU.NCE.ClusterTiling ([[FUNC_IN0]] as [[IN0_DDR:%.+]]: tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-NEXT:            VPU.Copy

    //CHECK:        [[CONV0_OUT:%.*]] = VPU.NCE.ClusterTiling ([[IN0_CMX]] as [[IN0:%.+]]: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[W0]] as [[INNER_W0:%.+]]: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[WT0]] as [[INNER_WT0:%.+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-NEXT:            VPU.NCE.Convolution([[IN0]], [[INNER_W0]], [[INNER_WT0]])

    //CHECK:        [[CONV0_DDR:%.*]] =  VPU.NCE.ClusterTiling ([[CONV0_OUT]] as [[IN_ARG:%.+]]: tensor<1x64x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
    //CHECK-SAME:       -> tensor<1x64x20x32xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-NEXT:            VPU.Copy

    //CHECK:        [[IN1_CMX:%.*]] = VPU.NCE.ClusterTiling ([[FUNC_IN1]] as [[IN1_DDR:%.+]]: tensor<1x32x20x32xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-NEXT:            VPU.Copy

    //CHECK:        [[CONV1_OUT:%.*]] = VPU.NCE.ClusterTiling ([[IN1_CMX]] as [[IN1:%.+]]: tensor<1x32x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[W1]] as [[INNER_W1:%.+]]: tensor<32x32x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    //CHECK-SAME:                [[WT1]] as [[INNER_WT1:%.+]]: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    //CHECK-SAME:                -> !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                        {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:                compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    //CHECK-SAME{LITERAL}:                compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    //CHECK-SAME{LITERAL}:                memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:                memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-NEXT:            VPU.NCE.Convolution([[IN1]], [[INNER_W1]], [[INNER_WT1]])

    //CHECK:        [[D_CAST0:%.*]] = VPU.DistributedCast([[CONV0_OUT]] :
    //CHECK-SAME:          !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:          -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                 {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:         compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:         compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:         memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:         memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        [[D_CAST1:%.*]] = VPU.DistributedCast([[CONV1_OUT]] :
    //CHECK-SAME:          !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 16, 20, 32], [1, 16, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:          -> !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN,
    //CHECK-SAME:                 {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:         compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:         compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:         memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:         memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        [[CONCAT_OUT:%.*]] = VPU.Concat([[D_CAST0]], [[D_CAST1]])
    //CHECK-SAME{LITERAL}:             {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} :
    //CHECK-SAME:       !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:       !VPU.DistributedTensor<1x32x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x96x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 96, 20, 32], [1, 96, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 96, 20, 32], [1, 96, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}>

    //CHECK:        VPU.NCE.ClusterTiling ([[CONCAT_OUT]] as [[ARG7:%.+]]: tensor<1x96x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x64x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED|SEGMENTED", num_tiles = [1, 2, 1, 1], num_clusters = 2 : i64
    //CHECK-SAME{LITERAL}:       compute_shapes = [[1, 32, 20, 32], [1, 32, 20, 32]],
    //CHECK-SAME{LITERAL}:       compute_offsets = [[0, 0, 0, 0], [0, 32, 0, 0]],
    //CHECK-SAME{LITERAL}:       memory_shapes = [[1, 64, 20, 32], [1, 64, 20, 32]],
    //CHECK-SAME{LITERAL}:       memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0]]}> {
    //CHECK:                VPU.NCE.Convolution([[ARG7]]

    //CHECK:        [[IN2_CMX:%.*]] = VPU.NCE.ClusterTiling ([[FUNC_IN2]] as [[IN2_DDR:%.+]]: tensor<1x16x10x16xf16, {mem_space = @DDR, order = #NHWC}>)
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x16x10x16xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-NEXT:           VPU.Copy

    //CHECK:        [[OUT_INTERP:%.*]] = VPU.NCE.ClusterTiling ([[IN2_CMX]] as [[ARG8:%.+]]: tensor<1x16x10x16xf16, {mem_space = @CMX_NN, order = #NHWC}>
    //CHECK-SAME:       -> !VPU.DistributedTensor<1x16x20x32xf16, #NHWC, @CMX_NN
    //CHECK-SAME:               {mode = "DUPLICATED", num_clusters = 2 : i64
    //CHECK-NEXT:           VPU.Interpolate([[ARG8]]

    //CHECK:        [[INTERP_DDR:%.*]] =  VPU.NCE.ClusterTiling ([[OUT_INTERP]] as [[ARG9:%.+]]: tensor<1x16x20x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
    //CHECK-SAME:       -> tensor<1x16x20x32xf16, {mem_space = @DDR, order = #NHWC}>
    //CHECK-NEXT:            VPU.Copy

    // CHECK:       VPU.Concat([[CONV0_DDR]], [[INTERP_DDR]])
    // CHECK-SAME:      -> tensor<1x80x20x32xf16, {mem_space = @DDR, order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x16x90x160xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 4, 1],
    num_clusters = 4 : i64,
    uniform_distributed_segments,
    compute_shapes = [[1, 16, 23, 160], [1, 16, 23, 160], [1, 16, 22, 160], [1, 16, 22, 160]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    memory_shapes = [[1, 16, 24, 160], [1, 16, 25, 160], [1, 16, 24, 160], [1, 16, 23, 160]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]
}>

!Distributed2 = !VPU.DistributedTensor<
    1x32x90x160xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 4, 1],
    num_clusters = 4 : i64,
    uniform_distributed_segments,
    compute_shapes = [[1, 32, 23, 160], [1, 32, 23, 160], [1, 32, 22, 160], [1, 32, 22, 160]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    memory_shapes = [[1, 32, 24, 160], [1, 32, 25, 160], [1, 32, 24, 160], [1, 32, 23, 160]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]
}>

// CHECK-LABEL: @SkipCMXConcatForNCEPermute
// CHECK-SAME:  ([[INPUT0:%.+]]: tensor<1x16x90x160xf16, {order = #NHWC}>,
// CHECK-SAME:  [[INPUT1:%.+]]: tensor<1x16x90x160xf16, {order = #NHWC}>)
func.func @SkipCMXConcatForNCEPermute(%arg0: tensor<1x16x90x160xf16, {order = #NHWC}>,
           %arg1: tensor<1x16x90x160xf16, {order = #NHWC}>)
           -> tensor<1x32x90x160xf16, {order = #NHWC}> {
    %maxPoolWeightsTable = const.Declare tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    %activationWindow = const.Declare tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>

    %maxPoolWeightsTable1 = const.Declare tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    %activationWindow1 = const.Declare tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>

    // Input 1 of Concat
    %0 = VPU.NCE.ClusterTiling (%arg0 as %arg2: tensor<1x16x90x160xf16, {order = #NHWC}>) -> !Distributed {
        %21 = VPU.Copy(%arg2) {out_mem_space = @CMX_NN} : tensor<1x16x90x160xf16, {order = #NHWC}> -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %1 = VPU.NCE.ClusterTiling (
        %0 as %arg2: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg3: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %activationWindow as %arg4: tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %21 = VPU.NCE.MaxPool(%arg2, %arg3, %arg4) {
                activation_window_channel_length = 4 : i64,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %2 = VPU.NCE.ClusterTiling (%1 as %arg2: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x90x160xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg2) : tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x90x160xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    // Input 2 of Concat
    %3 = VPU.NCE.ClusterTiling (%arg1 as %arg2: tensor<1x16x90x160xf16>) -> !Distributed {
        %21 = VPU.Copy(%arg2) {out_mem_space = @CMX_NN} : tensor<1x16x90x160xf16> -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NCHW}>
        VPU.Yield %21
    }

    %4 = VPU.NCE.ClusterTiling (%3 as %arg2: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NCHW}>) -> !Distributed {
        %21 = VPU.NCE.Permute(%arg2) {
            dstElemType = f16,
            dstOrder = #NHWC,
            expandedChannels = 16 : i64,
            ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
            lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>
        } -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %5 = VPU.NCE.ClusterTiling (%4 as %arg2: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x90x160xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg2) : tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x90x160xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    %6 = VPU.Concat(%2, %5) {static_offsets = [[0, 0, 0, 0], [0, 16, 0, 0]]} : tensor<1x16x90x160xf16, {order = #NHWC}>, tensor<1x16x90x160xf16, {order = #NHWC}> -> tensor<1x32x90x160xf16, {order = #NHWC}>

    // Concat output
    %7 = VPU.NCE.ClusterTiling (%6 as %arg2: tensor<1x32x90x160xf16, {order = #NHWC}>) -> !Distributed2 {
        %21 = VPU.Copy(%arg2) {out_mem_space = @CMX_NN} : tensor<1x32x90x160xf16, {order = #NHWC}> -> tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %8 = VPU.NCE.ClusterTiling (
        %7 as %arg2: tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable1 as %arg3: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %activationWindow1 as %arg4: tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed2 {
        %21 = VPU.NCE.MaxPool(%arg2, %arg3, %arg4) {
                activation_window_channel_length = 4 : i64,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %9 = VPU.NCE.ClusterTiling (%8 as %arg2: tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x32x90x160xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg2) : tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x32x90x160xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    return %9 : tensor<1x32x90x160xf16, {order = #NHWC}>

    // CHECK:       [[CST:%.+]] = const.Declare tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK:       [[CST_0:%.+]] = const.Declare tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK:       [[CST_1:%.+]] = const.Declare tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>

    // CHECK:       [[COPY_IN_0:%.+]] = VPU.NCE.ClusterTiling ([[INPUT0]] as [[ARG0:%[^:]+]]: tensor<1x16x90x160xf16, {order = #NHWC}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x16x90x160xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 4, 1], num_clusters = 4 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 16, 23, 160], [1, 16, 23, 160], [1, 16, 22, 160], [1, 16, 22, 160]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 16, 24, 160], [1, 16, 25, 160], [1, 16, 24, 160], [1, 16, 23, 160]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]}> {
    // CHECK:               VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x16x90x160xf16, {order = #NHWC}> -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[MAXPOOL_0:%.+]] = VPU.NCE.ClusterTiling (
    // CHECK-SAME:                          [[COPY_IN_0]] as [[ARG1:%[^:]+]]: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          [[CST]] as [[ARG2:%[^:]+]]: tensor<16x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
    // CHECK-SAME:                          [[CST_0]] as [[ARG3:%[^:]+]]: tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x16x90x160xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 4, 1], num_clusters = 4 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 16, 23, 160], [1, 16, 23, 160], [1, 16, 22, 160], [1, 16, 22, 160]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 16, 24, 160], [1, 16, 25, 160], [1, 16, 24, 160], [1, 16, 23, 160]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]}> {
    // CHECK:               VPU.NCE.MaxPool([[ARG1]], [[ARG2]] , [[ARG3]] ) {
    // CHECK-SAME:                  activation_window_channel_length = 4 : i64,
    // CHECK-SAME:                  kernel_size = [1, 1],
    // CHECK-SAME:                  pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:                  strides = [1, 1]}
    // CHECK-SAME:          -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_OUT_0:%.+]] = VPU.NCE.ClusterTiling ([[MAXPOOL_0]] as [[ARG4:%[^:]+]]: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x90x160xf16, {order = #NHWC}> {
    // CHECK:               VPU.Copy([[ARG4]]) : tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x90x160xf16, {order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_IN_1:%.+]] = VPU.NCE.ClusterTiling ([[INPUT1]] as [[ARG5:%[^:]+]]: tensor<1x16x90x160xf16>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x16x90x160xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 4, 1], num_clusters = 4 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 16, 23, 160], [1, 16, 23, 160], [1, 16, 22, 160], [1, 16, 22, 160]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 16, 24, 160], [1, 16, 25, 160], [1, 16, 24, 160], [1, 16, 23, 160]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]}> {
    // CHECK:               VPU.Copy([[ARG5]]) {out_mem_space = @CMX_NN} : tensor<1x16x90x160xf16> -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[NCE_PERMUTE:%.+]] = VPU.NCE.ClusterTiling ([[COPY_IN_1]] as [[ARG6:%[^:]+]]: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x16x90x160xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 4, 1], num_clusters = 4 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 16, 23, 160], [1, 16, 23, 160], [1, 16, 22, 160], [1, 16, 22, 160]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 16, 24, 160], [1, 16, 25, 160], [1, 16, 24, 160], [1, 16, 23, 160]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]}> {
    // CHECK:               VPU.NCE.Permute([[ARG6]]) {
    // CHECK-SAME:                  dstElemType = f16,
    // CHECK-SAME:                  dstOrder = #NHWC,
    // CHECK-SAME:                  expandedChannels = 16 : i64,
    // CHECK-SAME:                  ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
    // CHECK-SAME:                  lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>
    // CHECK-SAME:          } -> tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_OUT_1:%.+]] = VPU.NCE.ClusterTiling ([[NCE_PERMUTE]] as [[ARG7:%[^:]+]]: tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x16x90x160xf16, {order = #NHWC}> {
    // CHECK:               VPU.Copy([[ARG7]]) : tensor<1x16x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x16x90x160xf16, {order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[CMX_CONCAT:%.+]] = VPU.Concat([[COPY_OUT_0]], [[COPY_OUT_1]]) {
    // CHECK-SAME:          static_offsets = [
    // CHECK-SAME:              [0, 0, 0, 0],
    // CHECK-SAME:              [0, 16, 0, 0]
    // CHECK-SAME:          ]
    // CHECK-SAME:  } : tensor<1x16x90x160xf16, {order = #NHWC}>,
    // CHECK-SAME:      tensor<1x16x90x160xf16, {order = #NHWC}>
    // CHECK-SAME:      -> tensor<1x32x90x160xf16, {order = #NHWC}>

    // CHECK:       [[COPY_IN_2:%.+]] = VPU.NCE.ClusterTiling ([[CMX_CONCAT]] as [[ARG8:%[^:]+]]: tensor<1x32x90x160xf16, {order = #NHWC}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x32x90x160xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 4, 1], num_clusters = 4 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 32, 23, 160], [1, 32, 23, 160], [1, 32, 22, 160], [1, 32, 22, 160]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 32, 24, 160], [1, 32, 25, 160], [1, 32, 24, 160], [1, 32, 23, 160]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]}> {
    // CHECK:               VPU.Copy([[ARG8]]) {out_mem_space = @CMX_NN} : tensor<1x32x90x160xf16, {order = #NHWC}> -> tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[MAXPOOL_1:%.+]] = VPU.NCE.ClusterTiling (
    // CHECK-SAME:                          [[COPY_IN_2]] as [[ARG9:%[^:]+]]: tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          %cst_1 as [[ARG10:%[^:]+]]: tensor<32x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
    // CHECK-SAME:                          %cst_0 as [[ARG11:%[^:]+]]: tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x32x90x160xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 4, 1], num_clusters = 4 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 32, 23, 160], [1, 32, 23, 160], [1, 32, 22, 160], [1, 32, 22, 160]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 23, 0], [0, 0, 46, 0], [0, 0, 68, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 32, 24, 160], [1, 32, 25, 160], [1, 32, 24, 160], [1, 32, 23, 160]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 22, 0], [0, 0, 45, 0], [0, 0, 67, 0]]}> {
    // CHECK:               VPU.NCE.MaxPool([[ARG9]], [[ARG10]] , [[ARG11]] ) {
    // CHECK-SAME:                  activation_window_channel_length = 4 : i64,
    // CHECK-SAME:                  kernel_size = [1, 1],
    // CHECK-SAME:                  pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:                  strides = [1, 1]}
    // CHECK-SAME:          -> tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_OUT_2:%.+]] = VPU.NCE.ClusterTiling ([[MAXPOOL_1]] as [[ARG12:%[^:]+]]: tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x32x90x160xf16, {order = #NHWC}> {
    // CHECK:               VPU.Copy([[ARG12]]) : tensor<1x32x90x160xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x32x90x160xf16, {order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       return [[COPY_OUT_2]] : tensor<1x32x90x160xf16, {order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Distributed = !VPU.DistributedTensor<
    1x64x36x36xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 6, 1],
    num_clusters = 6 : i64,
    uniform_distributed_segments,
    compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]
}>

!Distributed2 = !VPU.DistributedTensor<
    64x64x1x1xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 6 : i64,
    uniform_distributed_segments,
    compute_shapes = [[64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
}>

!Distributed3 = !VPU.DistributedTensor<
    64x1x1x4xsi32, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 6 : i64,
    uniform_distributed_segments,
    compute_shapes = [[64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
}>

!Distributed4 = !VPU.DistributedTensor<
    64x16x1x1xf16, #NHWC, @CMX_NN, {
    mode = "DUPLICATED",
    num_clusters = 6 : i64,
    uniform_distributed_segments, compute_shapes = [[64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    memory_shapes = [[64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
}>

!Distributed5 = !VPU.DistributedTensor<
    1x128x36x36xf16, #NHWC, @CMX_NN, {
    mode = "OVERLAPPED",
    num_tiles = [1, 1, 6, 1],
    num_clusters = 6 : i64,
    uniform_distributed_segments,
    compute_shapes = [[1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36]],
    compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    memory_shapes = [[1, 128, 7, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 7, 36]],
    memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]
}>

// CHECK-LABEL: @InsertAvgPoolingWhenNCEOpHasExtraUser
// CHECK-SAME:  [[INPUT:%.+]]: tensor<1x64x36x36xf16, {order = #NHWC}>
func.func @InsertAvgPoolingWhenNCEOpHasExtraUser(%arg0: tensor<1x64x36x36xf16, {order = #NHWC}>)
           -> tensor<1x128x36x36xf16, {order = #NHWC}> {
    %convWeights = const.Declare tensor<64x64x1x1xf16, {order = #NHWC}> = dense<1.0> : tensor<64x64x1x1xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    %convWeightsTable = const.Declare tensor<64x1x1x4xsi32> = dense<1> : tensor<64x1x1x4xsi32>

    %dwConvWeights = const.Declare tensor<64x16x1x1xf16, {order = #NHWC}> = dense<1.0> : tensor<64x16x1x1xf16>, [#const.Reorder<#NHWC>]
    %dwConvWeightsTable = const.Declare tensor<64x1x1x4xsi32> = dense<1> : tensor<64x1x1x4xsi32>

    %maxPoolWeightsTable = const.Declare tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    %activationWindow = const.Declare tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}> =
        dense<1> : tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>

    // Input 1 of Concat
    %0 = VPU.NCE.ClusterTiling (%arg0 as %arg1: tensor<1x64x36x36xf16, {order = #NHWC}>) -> !Distributed {
        %21 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x64x36x36xf16, {order = #NHWC}> -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %1 = VPU.NCE.ClusterTiling (%convWeights as %arg1: tensor<64x64x1x1xf16, {order = #NHWC}>) -> !Distributed2 {
        %21 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<64x64x1x1xf16, {order = #NHWC}> -> tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %2 = VPU.NCE.ClusterTiling (%convWeightsTable as %arg1: tensor<64x1x1x4xsi32>) -> !Distributed3 {
        %21 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<64x1x1x4xsi32> -> tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
        VPU.Yield %21
    }
    %3 = VPU.NCE.ClusterTiling (
        %0 as %arg1: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %1 as %arg2: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %2 as %arg3: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %21 = VPU.NCE.Convolution(%arg1, %arg2, %arg3) {
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                ppe = #VPU.PPETask<mode = <LRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
                lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
                rawFilterShape = [64, 64, 1, 1],
                strides = [1, 1]
            } -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %4 = VPU.NCE.ClusterTiling (%3 as %arg1: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x64x36x36xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg1) : tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x36x36xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    // Input 2 of Concat
    %5 = VPU.NCE.ClusterTiling (%dwConvWeights as %arg1: tensor<64x16x1x1xf16, {order = #NHWC}>) -> !Distributed4 {
        %21 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<64x16x1x1xf16, {order = #NHWC}> -> tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %6 = VPU.NCE.ClusterTiling (%dwConvWeightsTable as %arg1: tensor<64x1x1x4xsi32>) -> !Distributed3 {
        %21 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<64x1x1x4xsi32> -> tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
        VPU.Yield %21
    }
    %7 = VPU.NCE.ClusterTiling (
        %3 as %arg1: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %5 as %arg2: tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %6 as %arg3: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed {
        %21 = VPU.NCE.DepthConvolution(%arg1, %arg2, %arg3) {
                pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
                ppe = #VPU.PPETask<mode = <LRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
                lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
                rawFilterShape = [64, 1, 3, 3],
                strides = [1, 1]
            } -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }
    %8 = VPU.NCE.ClusterTiling (%7 as %arg1: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x64x36x36xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg1) : tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x64x36x36xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    %9 = VPU.Concat(%4, %8) {static_offsets = [[0, 0, 0, 0], [0, 64, 0, 0]]} : tensor<1x64x36x36xf16, {order = #NHWC}>, tensor<1x64x36x36xf16, {order = #NHWC}> -> tensor<1x128x36x36xf16, {order = #NHWC}>

    // Concat output
    %10 = VPU.NCE.ClusterTiling (%9 as %arg1: tensor<1x128x36x36xf16, {order = #NHWC}>) -> !Distributed5 {
        %21 = VPU.Copy(%arg1) {out_mem_space = @CMX_NN} : tensor<1x128x36x36xf16, {order = #NHWC}> -> tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %11 = VPU.NCE.ClusterTiling (
        %10 as %arg1: tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>,
        %maxPoolWeightsTable as %arg2: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
        %activationWindow as %arg3: tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>)
            -> !Distributed5 {
        %21 = VPU.NCE.MaxPool(%arg1, %arg2, %arg3) {
                activation_window_channel_length = 4 : i64,
                pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
                strides = [1, 1],
                kernel_size = [1, 1]
            } -> tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
        VPU.Yield %21
    }

    %12 = VPU.NCE.ClusterTiling (%11 as %arg1: tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x36x36xf16, {order = #NHWC}> {
        %21 = VPU.Copy(%arg1) : tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x36x36xf16, {order = #NHWC}>
        VPU.Yield %21
    }

    return %12 : tensor<1x128x36x36xf16, {order = #NHWC}>

    // CHECK:       [[CST:%.+]] = const.Declare tensor<64x64x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<64x64x1x1xf32>, [#const.ConvertElemType<f16>, #const.Reorder<#NHWC>]
    // CHECK:       [[CST_0:%.+]] = const.Declare tensor<64x1x1x4xsi32> = dense<1> : tensor<64x1x1x4xsi32>
    // CHECK:       [[CST_1:%.+]] = const.Declare tensor<64x16x1x1xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<64x16x1x1xf16>, [#const.Reorder<#NHWC>]
    // CHECK:       [[CST_2:%.+]] = const.Declare tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK:       [[CST_3:%.+]] = const.Declare tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}> = dense<1> : tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>

    // CHECK:       [[COPY_IN_0:%.+]] = VPU.NCE.ClusterTiling ([[INPUT]] as [[ARG0:%[^:]+]]: tensor<1x64x36x36xf16, {order = #NHWC}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x64x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}> {
    // CHECK:               VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x64x36x36xf16, {order = #NHWC}> -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_IN_1:%.+]] = VPU.NCE.ClusterTiling ([[CST]] as [[ARG1:%[^:]+]]: tensor<64x64x1x1xf16, {order = #NHWC}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          64x64x1x1xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "DUPLICATED", num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1], [64, 64, 1, 1]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]}> {
    // CHECK:               VPU.Copy([[ARG1]]) {out_mem_space = @CMX_NN} : tensor<64x64x1x1xf16, {order = #NHWC}> -> tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_IN_2:%.+]] = VPU.NCE.ClusterTiling ([[CST_0]] as [[ARG2:%[^:]+]]: tensor<64x1x1x4xsi32>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          64x1x1x4xsi32, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "DUPLICATED", num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]}> {
    // CHECK:               VPU.Copy([[ARG2]]) {out_mem_space = @CMX_NN} : tensor<64x1x1x4xsi32> -> tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[CONV:%.+]] = VPU.NCE.ClusterTiling (
    // CHECK-SAME:                          [[COPY_IN_0]] as [[ARG3:%[^:]+]]: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          [[COPY_IN_1]] as [[ARG4:%[^:]+]]: tensor<64x64x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          [[COPY_IN_2]] as [[ARG5:%[^:]+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x64x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}> {
    // CHECK:               VPU.NCE.Convolution([[ARG3]], [[ARG4]], [[ARG5]]) {
    // CHECK-SAME:                  pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:                  ppe = #VPU.PPETask<mode = <LRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
    // CHECK-SAME:                  lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
    // CHECK-SAME:                  rawFilterShape = [64, 64, 1, 1],
    // CHECK-SAME:                  strides = [1, 1]}
    // CHECK-SAME:          -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[AVGPOOL:%.+]] = VPU.NCE.ClusterTiling ([[CONV]] as [[ARG6:%[^:]+]]: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x64x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}> {
    // CHECK:               VPU.NCE.AveragePool([[ARG6]]) {
    // CHECK-SAME:                  kernel_size = [1, 1],
    // CHECK-SAME:                  pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:                  ppe = #VPU.PPETask<mode = <NOOP>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
    // CHECK-SAME:                  lrelu_mult = 1 : i64, lrelu_shift = 0 : i64,
    // CHECK-SAME:                  quant_scale = [1.000000e+00]>,
    // CHECK-SAME:                  strides = [1, 1]}
    // CHECK-SAME:          -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_IN_3:%.+]] = VPU.NCE.ClusterTiling ([[CST_1]] as [[ARG7:%[^:]+]]: tensor<64x16x1x1xf16, {order = #NHWC}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          64x16x1x1xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "DUPLICATED", num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1], [64, 16, 1, 1]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]}> {
    // CHECK:               VPU.Copy([[ARG7]]) {out_mem_space = @CMX_NN} : tensor<64x16x1x1xf16, {order = #NHWC}> -> tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_IN_4:%.+]] = VPU.NCE.ClusterTiling ([[CST_0]] as [[ARG8:%[^:]+]]: tensor<64x1x1x4xsi32>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          64x1x1x4xsi32, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "DUPLICATED", num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4], [64, 1, 1, 4]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]}> {
    // CHECK:               VPU.Copy([[ARG8]]) {out_mem_space = @CMX_NN} : tensor<64x1x1x4xsi32> -> tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[DW_CONV:%.+]] = VPU.NCE.ClusterTiling (
    // CHECK-SAME:                          [[CONV]] as [[ARG9:%[^:]+]]: tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          [[COPY_IN_3]] as [[ARG10:%[^:]+]]: tensor<64x16x1x1xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          [[COPY_IN_4]] as [[ARG11:%[^:]+]]: tensor<64x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x64x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}> {
    // CHECK:               VPU.NCE.DepthConvolution([[ARG9]], [[ARG10]], [[ARG11]]) {
    // CHECK-SAME:                          pad = #VPU.Padding<left = 1 : i64, right = 1 : i64, top = 1 : i64, bottom = 1 : i64>,
    // CHECK-SAME:                          ppe = #VPU.PPETask<mode = <LRELU>, clamp_low = -2147483648 : i64, clamp_high = 2147483647 : i64,
    // CHECK-SAME:                          lrelu_mult = 1 : i64, lrelu_shift = 0 : i64, fp_prelu_alpha = 1.000000e+00 : f64>,
    // CHECK-SAME:                          rawFilterShape = [64, 1, 3, 3],
    // CHECK-SAME:                          strides = [1, 1]}
    // CHECK-SAME:          -> tensor<1x64x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[CMX_CONCAT:%.+]] = VPU.Concat([[AVGPOOL]], [[DW_CONV]]) {
    // CHECK-SAME:          static_offsets = [
    // CHECK-SAME:              [0, 0, 0, 0],
    // CHECK-SAME:              [0, 64, 0, 0]
    // CHECK-SAME:          ]} :
    // CHECK-SAME:              !VPU.DistributedTensor<
    // CHECK-SAME:                          1x64x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}>,
    // CHECK-SAME:              !VPU.DistributedTensor<
    // CHECK-SAME:                          1x64x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36], [1, 64, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 64, 7, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 8, 36], [1, 64, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}>
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x128x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                          compute_shapes = [[1, 128, 7, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 7, 36]],
    // CHECK-SAME{LITERAL}:                          compute_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]],
    // CHECK-SAME{LITERAL}:                          memory_shapes = [[1, 128, 7, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 7, 36]],
    // CHECK-SAME{LITERAL}:                          memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}>

    // CHECK:       [[MAXPOOL:%.+]] = VPU.NCE.ClusterTiling (
    // CHECK-SAME:                          [[CMX_CONCAT]] as [[ARG12:%[^:]+]]: tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>,
    // CHECK-SAME:                          [[CST_2]] as [[ARG13:%[^:]+]]: tensor<128x1x1x4xsi32, {mem_space = @CMX_NN, order = #NCHW}>,
    // CHECK-SAME:                          [[CST_3]] as [[ARG14:%[^:]+]]: tensor<1x1x1x16xui8, {mem_space = @CMX_NN, order = #NCHW}>)
    // CHECK-SAME:                      -> !VPU.DistributedTensor<
    // CHECK-SAME:                          1x128x36x36xf16, #NHWC, @CMX_NN, {
    // CHECK-SAME:                          mode = "OVERLAPPED", num_tiles = [1, 1, 6, 1], num_clusters = 6 : i64, uniform_distributed_segments,
    // CHECK-SAME{LITERAL}:                 compute_shapes = [[1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36], [1, 128, 6, 36]],
    // CHECK-SAME{LITERAL}:                 compute_offsets = [[0, 0, 0, 0], [0, 0, 6, 0], [0, 0, 12, 0], [0, 0, 18, 0], [0, 0, 24, 0], [0, 0, 30, 0]],
    // CHECK-SAME{LITERAL}:                 memory_shapes = [[1, 128, 7, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 8, 36], [1, 128, 7, 36]],
    // CHECK-SAME{LITERAL}:                 memory_offsets = [[0, 0, 0, 0], [0, 0, 5, 0], [0, 0, 11, 0], [0, 0, 17, 0], [0, 0, 23, 0], [0, 0, 29, 0]]}> {
    // CHECK:               VPU.NCE.MaxPool([[ARG12]], [[ARG13]] , [[ARG14]] ) {
    // CHECK-SAME:                          activation_window_channel_length = 4 : i64,
    // CHECK-SAME:                          kernel_size = [1, 1],
    // CHECK-SAME:                          pad = #VPU.Padding<left = 0 : i64, right = 0 : i64, top = 0 : i64, bottom = 0 : i64>,
    // CHECK-SAME:                          strides = [1, 1]}
    // CHECK-SAME:          -> tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       [[COPY_OUT:%.+]] = VPU.NCE.ClusterTiling ([[MAXPOOL]] as [[ARG15:%[^:]+]]: tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x36x36xf16, {order = #NHWC}> {
    // CHECK:               VPU.Copy([[ARG15]]) : tensor<1x128x36x36xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x36x36xf16, {order = #NHWC}>
    // CHECK:               VPU.Yield
    // CHECK:       }

    // CHECK:       return [[COPY_OUT]] : tensor<1x128x36x36xf16, {order = #NHWC}>
}
