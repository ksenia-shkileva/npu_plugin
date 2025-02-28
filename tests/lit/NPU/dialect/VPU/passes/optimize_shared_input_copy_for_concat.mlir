//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --optimize-shared-input-copy-for-concat %s | FileCheck %s
// REQUIRES: arch-NPU37XX || arch-NPU40XX


#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Input_CMX = tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
!Output_CMX = tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK-LABEL: @OptimizeSharedInputCopyForConcat
// CHECK-SAME: ([[INPUT0:%.*]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>, [[INPUT1:%.*]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>)
func.func @OptimizeSharedInputCopyForConcat(%input0: !Input_CMX, %input1: !Input_CMX) -> (!Output_CMX, !Output_CMX) {
    %cst0 = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]
    %cst1 = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]

    %conv_out0 = VPU.Copy(%input0) {out_mem_space = @DDR} : !Input_CMX -> tensor<1x128x16x32xf16, {order = #NHWC}>
    %conv_out1 = VPU.Copy(%input1) {out_mem_space = @DDR} : !Input_CMX -> tensor<1x128x16x32xf16, {order = #NHWC}>

    %concat_output = VPU.Concat(%conv_out0, %conv_out1) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    %concat0 = VPU.Concat(%concat_output , %cst0) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>
    %concat1 = VPU.Concat(%concat_output , %cst1) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>

    %slice0 = VPU.Slice %concat0 [0, 0, 0, 0] [1, 256, 16, 32] : tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x256x16x32xf16, {order = #NHWC}>
    %slice1 = VPU.Slice %concat1 [0, 0, 0, 0] [1, 256, 16, 32] : tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x256x16x32xf16, {order = #NHWC}>

    %output0 = VPU.Copy(%slice0) { out_mem_space = @CMX_NN } : tensor<1x256x16x32xf16, {order = #NHWC}> -> !Output_CMX
    %output1 = VPU.Copy(%slice1) { out_mem_space = @CMX_NN } : tensor<1x256x16x32xf16, {order = #NHWC}> -> !Output_CMX
    return %output0, %output1 : !Output_CMX, !Output_CMX

    // CHECK-DAG: [[CST0:%.*]] = const.Declare tensor<1x128x16x32xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 128, 16, 32]>]
    // CHECK-DAG: [[CST1:%.*]] = const.Declare tensor<1x128x16x32xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 128, 16, 32]>]

    // CHECK:     [[CST0_COPY:%.*]] = VPU.Copy([[CST0]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:     [[CST1_COPY:%.*]] = VPU.Copy([[CST1]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK:     [[INPUT0_COPY:%.*]] = VPU.Copy([[INPUT0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:     [[INPUT1_COPY:%.*]] = VPU.Copy([[INPUT1]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>

    // CHECK:     [[DDR_CONCAT:%.*]] = VPU.Concat([[INPUT0_COPY]], [[INPUT1_COPY]])
    // CHECK-SAME{LITERAL}:  {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    // CHECK:     [[SLICE0:%.*]] = VPU.Slice [[DDR_CONCAT]] [0, 0, 0, 0] [1, 128, 16, 32] : tensor<1x128x16x64xf16, {order = #NHWC}> to tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:     [[SLICE0_COPY:%.*]] = VPU.Copy([[SLICE0]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK:     [[SLICE1:%.*]] = VPU.Slice [[DDR_CONCAT]] [0, 0, 0, 0] [1, 128, 16, 32] : tensor<1x128x16x64xf16, {order = #NHWC}> to tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:     [[SLICE1_COPY:%.*]] = VPU.Copy([[SLICE1]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

    // CHECK:     [[CMX_CONCAT0:%.*]] = VPU.Concat([[SLICE0_COPY]], [[CST0_COPY]])
    // CHECK-SAME{LITERAL}: {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:     [[CMX_CONCAT1:%.*]] = VPU.Concat([[SLICE1_COPY]], [[CST1_COPY]])
    // CHECK-SAME{LITERAL}: {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:     return [[CMX_CONCAT0]], [[CMX_CONCAT1]] : tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>, tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Input_Distributed = !VPU.DistributedTensor<
    1x128x16x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64
}>

!Output_Distributed = !VPU.DistributedTensor<
    1x128x16x64xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64
}>

!Input_DDR = tensor<1x128x16x64xf16, {order = #NHWC}>

!InputStub_CMX = tensor<1x128x16x64xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK-LABEL: @OptimizeSharedClusteredInputCopyForConcatOnSameAxis
// CHECK-SAME: ([[INPUT0:%.+]]: !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, [[INPUT1:%.+]]: !VPU.DistributedTensor<1
func.func @OptimizeSharedClusteredInputCopyForConcatOnSameAxis(%input0: !Input_Distributed, %input1: !Input_Distributed) -> (!Output_Distributed, !Output_Distributed) {
    %cst0 = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]
    %cst1 = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]

    %conv_out0 = VPU.NCE.ClusterTiling (%input0 as %arg0: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg0) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %0
    }
    %conv_out1 = VPU.NCE.ClusterTiling (%input1 as %arg0: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg0) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %0
    }

    %concat_output = VPU.Concat(%conv_out0, %conv_out1) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    %concat0 = VPU.Concat(%concat_output , %cst0) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>
    %concat1 = VPU.Concat(%concat_output , %cst1) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>

    %slice0 = VPU.Slice %concat0 [0, 32, 0, 0] [1, 128, 16, 64] :tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x128x16x64xf16, {order = #NHWC}>
    %slice1 = VPU.Slice %concat1 [0, 32, 0, 0] [1, 128, 16, 64] :tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x128x16x64xf16, {order = #NHWC}>

    %output0 = VPU.NCE.ClusterTiling(%slice0 as %arg0: tensor<1x128x16x64xf16, {order = #NHWC}>) -> !Output_Distributed {
        %0 = VPU.Copy(%arg0) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }
    %output1 = VPU.NCE.ClusterTiling(%slice1 as %arg0: tensor<1x128x16x64xf16, {order = #NHWC}>) -> !Output_Distributed {
        %0 = VPU.Copy(%arg0) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }
    return %output0, %output1 : !Output_Distributed, !Output_Distributed

    // CHECK-DAG:    [[CST0:%.*]] = const.Declare tensor<1x32x16x64xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 32, 16, 64]>]
    // CHECK-DAG:    [[CST1:%.*]] = const.Declare tensor<1x32x16x64xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 32, 16, 64]>]

    // CHECK:    [[CST0_COPY:%.*]] = VPU.NCE.ClusterTiling ([[CST0]] as [[ARG0:%.*]]: tensor<1x32x16x64xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x32x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x32x16x64xf16, {order = #NHWC}> -> tensor<1x32x16x64xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }
    // CHECK:    [[CST1_COPY:%.*]] = VPU.NCE.ClusterTiling ([[CST1]] as [[ARG0:%.*]]: tensor<1x32x16x64xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x32x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x32x16x64xf16, {order = #NHWC}> -> tensor<1x32x16x64xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }

    // CHECK:    [[INPUT0_COPY:%.*]] = VPU.NCE.ClusterTiling ([[INPUT0]] as [[ARG0]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:    }
    // CHECK:    [[INPUT1_COPY:%.*]] = VPU.NCE.ClusterTiling ([[INPUT1]] as [[ARG0]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:    }

    // CHECK:    [[DDR_CONCAT:%.*]] = VPU.Concat([[INPUT0_COPY]], [[INPUT1_COPY]])
    // CHECK-SAME{LITERAL}:          {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    // CHECK:    [[SLICE0:%.*]] = VPU.Slice [[DDR_CONCAT]] [0, 32, 0, 0] [1, 96, 16, 64] : tensor<1x128x16x64xf16, {order = #NHWC}> to tensor<1x96x16x64xf16, {order = #NHWC}>
    // CHECK:    [[SLICE0_COPY:%.*]] = VPU.NCE.ClusterTiling ([[SLICE0]] as [[ARG0:%.*]]: tensor<1x96x16x64xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x96x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x96x16x64xf16, {order = #NHWC}> -> tensor<1x96x16x64xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }
    // CHECK:    [[SLICE1:%.*]] = VPU.Slice [[DDR_CONCAT]] [0, 32, 0, 0] [1, 96, 16, 64] : tensor<1x128x16x64xf16, {order = #NHWC}> to tensor<1x96x16x64xf16, {order = #NHWC}>
    // CHECK:    [[SLICE1_COPY:%.*]] = VPU.NCE.ClusterTiling ([[SLICE1]] as [[ARG0:%.*]]: tensor<1x96x16x64xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x96x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x96x16x64xf16, {order = #NHWC}> -> tensor<1x96x16x64xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }
    // CHECK:    [[CMX_CONCAT0:%.*]] = VPU.Concat([[SLICE0_COPY]], [[CST0_COPY]])
    // CHECK-SAME{LITERAL}:           {static_offsets = [[0, 0, 0, 0], [0, 96, 0, 0]]} : !VPU.DistributedTensor<1x96x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x32x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> -> !VPU.DistributedTensor<1x128x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CMX_CONCAT1:%.*]] = VPU.Concat([[SLICE1_COPY]], [[CST1_COPY]])
    // CHECK-SAME{LITERAL}:           {static_offsets = [[0, 0, 0, 0], [0, 96, 0, 0]]} : !VPU.DistributedTensor<1x96x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x32x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> -> !VPU.DistributedTensor<1x128x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    return [[CMX_CONCAT0]], [[CMX_CONCAT1]] : !VPU.DistributedTensor<1x128x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x128x16x64xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
}

// -----

#NCHW = affine_map<(d0, d1, d2, d3) -> (d0, d1, d2, d3)>
#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Input_Distributed = !VPU.DistributedTensor<
    1x128x16x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64
}>

!Output_Distributed = !VPU.DistributedTensor<
    1x256x16x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64
}>

!Input_DDR = tensor<1x256x16x32xf16, {order = #NHWC}>

!InputStub_CMX = tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>

// CHECK-LABEL: @OptimizeSharedClusteredInputCopyForConcatOnDifferentAxes
// CHECK-SAME: ([[INPUT0:%.+]]: !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, [[INPUT1:%.+]]: !VPU.DistributedTensor
func.func @OptimizeSharedClusteredInputCopyForConcatOnDifferentAxes(%input0: !Input_Distributed, %input1: !Input_Distributed) -> (!Output_Distributed, !Output_Distributed) {
    %cst0 = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]
    %cst1 = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]

    %conv_out0 = VPU.NCE.ClusterTiling (%input0 as %arg0: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg0) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %0
    }
    %conv_out1 = VPU.NCE.ClusterTiling (%input1 as %arg0: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg0) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %0
    }

    %concat_output = VPU.Concat(%conv_out0, %conv_out1) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    %concat0 = VPU.Concat(%concat_output , %cst0) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>
    %concat1 = VPU.Concat(%concat_output , %cst1) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>

    %slice0 = VPU.Slice %concat0 [0, 0, 0, 0] [1, 256, 16, 32] : tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x256x16x32xf16, {order = #NHWC}>
    %slice1 = VPU.Slice %concat1 [0, 0, 0, 0] [1, 256, 16, 32] : tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x256x16x32xf16, {order = #NHWC}>

    %output0 = VPU.NCE.ClusterTiling(%slice0 as %arg0: tensor<1x256x16x32xf16, {order = #NHWC}>) -> !Output_Distributed {
        %0 = VPU.Copy(%arg0) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }
    %output1 = VPU.NCE.ClusterTiling(%slice1 as %arg0: tensor<1x256x16x32xf16, {order = #NHWC}>) -> !Output_Distributed {
        %0 = VPU.Copy(%arg0) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }
    return %output0, %output1 : !Output_Distributed, !Output_Distributed

    // CHECK-DAG:    [[CST0:%.*]] = const.Declare tensor<1x128x16x32xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 128, 16, 32]>]
    // CHECK-DAG:    [[CST1:%.*]] = const.Declare tensor<1x128x16x32xf16, {order = #NHWC}> = dense<1.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>, #const.SubView<[0, 0, 0, 0], [1, 128, 16, 32]>]

    // CHECK:    [[CST0_COPY:%.*]] = VPU.NCE.ClusterTiling ([[CST0]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }
    // CHECK:    [[CST1_COPY:%.*]] = VPU.NCE.ClusterTiling ([[CST1]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }


    // CHECK:    [[INPUT0_COPY:%.*]] = VPU.NCE.ClusterTiling ([[INPUT0]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:    }
    // CHECK:    [[INPUT1_COPY:%.*]] = VPU.NCE.ClusterTiling ([[INPUT1]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
    // CHECK:                        VPU.Copy([[ARG0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:    }

    // CHECK:    [[DDR_CONCAT:%.*]] = VPU.Concat([[INPUT0_COPY]], [[INPUT1_COPY]])
    // CHECK-SAME{LITERAL}:            {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    // CHECK:    [[SLICE0:%.*]] = VPU.Slice [[DDR_CONCAT]] [0, 0, 0, 0] [1, 128, 16, 32] : tensor<1x128x16x64xf16, {order = #NHWC}> to tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:    [[SLICE0_COPY:%.*]] = VPU.NCE.ClusterTiling ([[SLICE0]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                         VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }

    // CHECK:    [[SLICE1:%.*]] = VPU.Slice [[DDR_CONCAT]] [0, 0, 0, 0] [1, 128, 16, 32] : tensor<1x128x16x64xf16, {order = #NHWC}> to tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:    [[SLICE1_COPY:%.*]] = VPU.NCE.ClusterTiling ([[SLICE1]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                         VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:    }

    // CHECK:    [[CMX_CONCAT0:%.*]] = VPU.Concat([[SLICE0_COPY]], [[CST0_COPY]])
    // CHECK-SAME{LITERAL}:            {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> -> !VPU.DistributedTensor<1x256x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
    // CHECK:    [[CMX_CONCAT1:%.*]] = VPU.Concat([[SLICE1_COPY]], [[CST1_COPY]])
    // CHECK-SAME{LITERAL}:            {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> -> !VPU.DistributedTensor<1x256x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>

    // CHECK:    return [[CMX_CONCAT0]], [[CMX_CONCAT1]] : !VPU.DistributedTensor<1x256x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, !VPU.DistributedTensor<1x256x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>

!Input_Distributed = !VPU.DistributedTensor<
    1x128x16x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64
}>

!Output_Distributed = !VPU.DistributedTensor<
    1x256x16x32xf16, #NHWC, @CMX_NN, {
    mode = "SEGMENTED",
    num_tiles = [1, 1, 2, 1],
    num_clusters = 2 : i64
}>

!Input_DDR = tensor<1x256x16x32xf16, {order = #NHWC}>

!InputStub_CMX = tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>



// CHECK-LABEL: @NotOptimizeSharedInputCopyForSingConcatUser
// CHECK-SAME: ([[INPUT0:%.+]]: !VPU.DistributedTensor<1x128x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>, [[INPUT1:%.+]]: !VPU.DistributedTensor
func.func @NotOptimizeSharedInputCopyForSingConcatUser(%input0: !Input_Distributed, %input1: !Input_Distributed) -> !Output_Distributed {
    %cst = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]

    %conv_out0 = VPU.NCE.ClusterTiling (%input0 as %arg0: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg0) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %0
    }
    %conv_out1 = VPU.NCE.ClusterTiling (%input1 as %arg0: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
        %0 = VPU.Copy(%arg0) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
        VPU.Yield %0
    }

    %concat0 = VPU.Concat(%conv_out0, %conv_out1) {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>

    %concat1 = VPU.Concat(%concat0, %cst) {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>

    %slice0 = VPU.Slice %concat1 [0, 0, 0, 0] [1, 256, 16, 32] : tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x256x16x32xf16, {order = #NHWC}>

    %output0 = VPU.NCE.ClusterTiling(%slice0 as %arg0: tensor<1x256x16x32xf16, {order = #NHWC}>) -> !Output_Distributed {
        %0 = VPU.Copy(%arg0) { out_mem_space = @CMX_NN } : !Input_DDR -> !InputStub_CMX
        VPU.Yield %0
    }
    return %output0 : !Output_Distributed

    // CHECK:   [[CST:%.*]] = const.Declare tensor<1x128x16x64xf16, {order = #NHWC}> = dense<0.000000e+00> : tensor<1x128x16x64xf16>, [#const.Reorder<#NHWC>]
    // CHECK:   [[COPY0:%.*]] = VPU.NCE.ClusterTiling ([[INPUT0]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
    // CHECK:                   VPU.Copy([[ARG0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:   }
    // CHECK:   [[COPY1:%.*]] = VPU.NCE.ClusterTiling ([[INPUT1]] as [[ARG0:%.*]]: tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>) -> tensor<1x128x16x32xf16, {order = #NHWC}> {
    // CHECK:                   VPU.Copy([[ARG0]]) {out_mem_space = @DDR} : tensor<1x128x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}> -> tensor<1x128x16x32xf16, {order = #NHWC}>
    // CHECK:   }

    // CHECK:   [[CONCAT0:%.*]] = VPU.Concat([[COPY0]], [[COPY1]])
    // CHECK-SAME{LITERAL}: {static_offsets = [[0, 0, 0, 0], [0, 0, 0, 32]]} : tensor<1x128x16x32xf16, {order = #NHWC}>, tensor<1x128x16x32xf16, {order = #NHWC}> -> tensor<1x128x16x64xf16, {order = #NHWC}>
    // CHECK:   [[CONCAT1:%.*]] = VPU.Concat([[CONCAT0]], [[CST]])
    // CHECK-SAME{LITERAL}: {static_offsets = [[0, 0, 0, 0], [0, 128, 0, 0]]} : tensor<1x128x16x64xf16, {order = #NHWC}>, tensor<1x128x16x64xf16, {order = #NHWC}> -> tensor<1x256x16x64xf16, {order = #NHWC}>

    // CHECK:   [[SLICE:%.*]] = VPU.Slice [[CONCAT1]] [0, 0, 0, 0] [1, 256, 16, 32] : tensor<1x256x16x64xf16, {order = #NHWC}> to tensor<1x256x16x32xf16, {order = #NHWC}>
    // CHECK:   [[COPY2:%.*]] = VPU.NCE.ClusterTiling ([[SLICE]] as [[ARG0:%.*]]: tensor<1x256x16x32xf16, {order = #NHWC}>) -> !VPU.DistributedTensor<1x256x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}> {
    // CHECK:                   VPU.Copy([[ARG0]]) {out_mem_space = @CMX_NN} : tensor<1x256x16x32xf16, {order = #NHWC}> -> tensor<1x256x16x32xf16, {mem_space = @CMX_NN, order = #NHWC}>
    // CHECK:   }
    // CHECK:   return [[COPY2]] : !VPU.DistributedTensor<1x256x16x32xf16, #NHWC, @CMX_NN, {mode = "SEGMENTED", num_tiles = [1, 1, 2, 1], num_clusters = 2 : i64}>
}
