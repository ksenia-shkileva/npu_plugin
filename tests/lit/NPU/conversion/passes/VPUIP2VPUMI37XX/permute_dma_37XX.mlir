//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//
// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch% compilation-mode=DefaultHW" --convert-VPUIP-to-VPUMI37XX %s | FileCheck %s
// REQUIRES: arch-NPU37XX

module @permuteDMA {
  func.func @main(%arg0: memref<16x256xf16, @DDR>, %arg1: memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR> {
    %0 = VPURT.DeclareBuffer <NetworkInput> [0] <0> -> memref<16x256xf16, @DDR>
    %1 = VPURT.DeclareBuffer <NetworkOutput> [0] <0> -> memref<256x16xf16, @DDR>
    VPURT.Task attributes {isTrailingSWLayer = false} {
      %3 = VPUIP.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %4 =  VPUIP.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %5 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) -> memref<256x16xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %6 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) -> memref<256x16xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %7 =  VPUIP.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %8 =  VPUIP.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR>
    }

    return %arg1 : memref<16x256xf16, @DDR>
  }
}

// CHECK-NOT: VPUIP.NNDMA
// CHECK: %[[VAL5:.*]] = VPUMI37XX.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:5>
// CHECK-NOT: VPUIP.NNDMA
// CHECK: %[[VAL4:.*]] = VPUMI37XX.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) nextDMAIdx(%[[VAL5]] : !VPURegMapped.Index<0:0:5>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:4>
// CHECK-NOT: VPUIP.PermuteDMA
// CHECK: %[[VAL3:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) nextDMAIdx(%[[VAL4]] : !VPURegMapped.Index<0:0:4>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:3>
// CHECK-NOT: VPUIP.PermuteDMA
// CHECK: %[[VAL2:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) nextDMAIdx(%[[VAL3]] : !VPURegMapped.Index<0:0:3>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:2>
// CHECK-NOT: VPUIP.NNDMA
// CHECK: %[[VAL1:.*]] = VPUMI37XX.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) nextDMAIdx(%[[VAL2]] : !VPURegMapped.Index<0:0:2>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:1>
// CHECK-NOT: VPUIP.NNDMA
// CHECK: %[[VAL0:.*]] = VPUMI37XX.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) nextDMAIdx(%[[VAL1]] : !VPURegMapped.Index<0:0:1>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:0>

// -----

module @permuteDMA {
  func.func @main(%arg0: memref<16x256xf16, @DDR>, %arg1: memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR> {
    %0 = VPURT.DeclareBuffer <NetworkInput> [0] <0> -> memref<16x256xf16, @DDR>
    %1 = VPURT.DeclareBuffer <NetworkOutput> [0] <0> -> memref<256x16xf16, @DDR>

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %2 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) -> memref<256x16xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %3 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) -> memref<256x16xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %4 = VPUIP.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %5 =  VPUIP.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) -> memref<16x256xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %6 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) -> memref<256x16xf16, @DDR>
    }

    VPURT.Task attributes {isTrailingSWLayer = false} {
      %7 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) -> memref<256x16xf16, @DDR>
    }

    return %arg1 : memref<16x256xf16, @DDR>
  }
}

// CHECK-NOT: VPUIP.PermuteDMA
// CHECK: %[[VAL5:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:5>
// CHECK-NOT: VPUIP.PermuteDMA
// CHECK: %[[VAL4:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) nextDMAIdx(%[[VAL5]] : !VPURegMapped.Index<0:0:5>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:4>
// CHECK-NOT: VPUIP.NNDMA
// CHECK: %[[VAL3:.*]] = VPUMI37XX.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) nextDMAIdx(%[[VAL4]] : !VPURegMapped.Index<0:0:4>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:3>
// CHECK-NOT: VPUIP.NNDMA
// CHECK: %[[VAL2:.*]] = VPUMI37XX.NNDMA {port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%0 : memref<16x256xf16, @DDR>) nextDMAIdx(%[[VAL3]] : !VPURegMapped.Index<0:0:3>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:2>
// CHECK-NOT: VPUIP.PermuteDMA
// CHECK: %[[VAL1:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) nextDMAIdx(%[[VAL2]] : !VPURegMapped.Index<0:0:2>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:1>
// CHECK-NOT: VPUIP.PermuteDMA
// CHECK: %[[VAL0:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%0 : memref<16x256xf16, @DDR>) outputs(%1 : memref<256x16xf16, @DDR>) nextDMAIdx(%[[VAL1]] : !VPURegMapped.Index<0:0:1>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:0>

// -----

#NC = affine_map<(d0, d1) -> (d0, d1)>
module @PermuteDMA {
func.func @UnrollDistributedPermuteDMAOutput(%arg0: memref<1x16x16x16xf16, @DDR>, %arg1: memref<64x32x1x1xf16, @DDR>) -> memref<64x32x1x1xf16, @DDR> {
  %cst = const.Declare memref<16x256xf16, #NC, @DDR> = dense<1.000000e+00> : tensor<16x256xf16>, [#const.Reorder<#NC>]
  // CHECK-DAG: %[[CST:.*]] = const.Declare memref<16x256xf16, @DDR>

  %3 = VPURT.DeclareBuffer <CMX_NN> [0, 1] <0> -> !VPUIP.DistributedBuffer<16x256xf16, {order = #NC, strides = [256, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
  // CHECK: %[[WEIGHTS:.*]] = VPURT.DeclareBuffer <CMX_NN> [0, 1] <0> -> !VPUIP.DistributedBuffer<16x256xf16, {order = #NC, strides = [256, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>

  VPURT.Task attributes {isTrailingSWLayer = false} {
    %4 = VPUIP.PermuteDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%cst : memref<16x256xf16, #NC, @DDR>) outputs(%3 : !VPUIP.DistributedBuffer<16x256xf16, {order = #NC, strides = [256, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>) -> !VPUIP.DistributedBuffer<16x256xf16, {order = #NC, strides = [256, 1]}, @CMX_NN, {mode = "DUPLICATED", num_clusters = 2 : i64}>
  }
  // CHECK: %[[BUFF_TILE_0:.*]] = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<16x256xf16, [@CMX_NN, 0]>
  // CHECK: %[[BUFF_TILE_1:.*]] = VPURT.DeclareBuffer <CMX_NN> [1] <0> -> memref<16x256xf16, [@CMX_NN, 1]>
  // CHECK-NOT: VPURT.Task
  // CHECK: %[[DMA0:.*]] = VPUMI37XX.NNDMA {dma_descriptor = #VPUIP.DMADescriptorAttr<numPlanes = 16 : i64, len = 512 : i64, srcWidth = 512 : i64, srcStride = 2 : i64, srcPlaneStride = 512 : i64, dstWidth = 2 : i64, dstStride = 32 : i64, dstPlaneStride = 2 : i64>, port = 0 : i64} inputs(%[[CST]] : memref<16x256xf16, @DDR>) outputs(%[[BUFF_TILE_0]], %[[BUFF_TILE_1]] : memref<16x256xf16, [@CMX_NN, 0]>, memref<16x256xf16, [@CMX_NN, 1]>) start_after(0) clean_after(0) acceleration_mode(<DISABLE>) -> !VPURegMapped.Index<0:0:0>

  return %arg1 : memref<64x32x1x1xf16, @DDR>
}
}
