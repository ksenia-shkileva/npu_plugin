//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --init-compiler="vpu-arch=%arch% allow-custom-values=true" --convert-VPUMI37XX-to-ELF %s | FileCheck %s
// REQUIRES: arch-NPU37XX

module @Test attributes {VPU.arch = #VPU.arch_kind<NPU37XX>, VPU.compilationMode = #VPU.compilation_mode<ReferenceHW>} {
  IE.MemoryResource 31457280 bytes of @DDR {VPU.bandwidth = 8 : i64, VPU.derateFactor = 6.000000e-01 : f64}
  IE.ExecutorResource 1 of @DMA_NN
  IE.TileResource 1 of @NCE {
    IE.MemoryResource 2097152 bytes of @CMX_NN {VPU.bandwidth = 32 : i64, VPU.derateFactor = 1.000000e+00 : f64}
    IE.ExecutorResource 1 of @SHAVE_UPA
    IE.ExecutorResource 1 of @SHAVE_ACT
    IE.ExecutorResource 1 of @DPU
  }
  IE.CNNNetwork entryPoint : @main inputsInfo : {
    DataInfo "input" : tensor<1x1000xf16>
  } outputsInfo : {
    DataInfo "softmax" : tensor<1x1000xf16>
  }
  module @VPU.SW {
    func.func private @builtin_softmax(memref<*xf16>, memref<*xf16>, i64) attributes {VPU.kernel_code = "softmax.cpp", VPU.kernel_entry = "softmax"}
  }
  func.func @main(%arg0: memref<1x1x1x1000xf16>, %arg1: memref<1x1x1x1000xf16>) -> memref<1x1x1x1000xf16> {
    %0 = VPURT.DeclareBuffer <CMX_NN> [0] <0> -> memref<1x1x1x1000xf16, [@CMX_NN, 0]>
    %1 = VPURT.DeclareBuffer <CMX_NN> [0] <2000> -> memref<1x1x1x1000xf16, [@CMX_NN, 0]>
    %2 = VPUMI37XX.ConfigureBarrier {consumer_count = 1 : ui8, producer_count = 1 : ui8}<0, -1> -> !VPURegMapped.Index<0:0:0>
    %3 = VPUMI37XX.ConfigureBarrier {consumer_count = 1 : ui8, producer_count = 1 : ui8}<1, -1> -> !VPURegMapped.Index<0:0:1>
    %5 = VPUMI37XX.DeclareKernelText kernel_path("softmax_3720xx") -> !VPURegMapped.Index<0:0:0>
    %6 = VPUMI37XX.DeclareKernelArgs kernel_path("softmax_3720xx") -> !VPURegMapped.Index<0:0:0>
    %7 = VPUMI37XX.DeclareKernelEntry kernel_path("softmax_3720xx") -> !VPURegMapped.Index<0:0:0>
    %8 = VPUMI37XX.ActKernelRange kernel_text_index(%5 : !VPURegMapped.Index<0:0:0>) kernel_args_index(%6 : !VPURegMapped.Index<0:0:0>) kernel_entry_index(%7 : !VPURegMapped.Index<0:0:0>) kernelTaskType(@COMPUTE) -> !VPURegMapped.Index<0:0:0>
    %10 = VPUMI37XX.KernelParams inputs(%0 : memref<1x1x1x1000xf16, [@CMX_NN, 0]>) outputs(%1 : memref<1x1x1x1000xf16, [@CMX_NN, 0]>) kernel_type("softmax") kernel_params(dense<[0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 67, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 67, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]> : vector<80xui8>) -> !VPURegMapped.Index<0:0:0>
    %9 = VPUMI37XX.ActKernelInvocation range_index(%8 : <0:0:0>) params_index(%10 : !VPURegMapped.Index<0:0:0>) waits(%2 : !VPURegMapped.Index<0:0:0>) updates(%3 : !VPURegMapped.Index<0:0:1>) tile(0) start_after(0) clean_after(0) -> !VPURegMapped.Index<0:0:0>
    %12 = VPUMI37XX.MappedInference actKernelRanges(%8 : !VPURegMapped.Index<0:0:0>) actKernelInvocations(%9 : !VPURegMapped.Index<0:0:0>) barriers(%2 : !VPURegMapped.Index<0:0:0>) dmaCount([0]) invariantCount(0) variantCount(0) actKernelRangesCount(1) actKernelInvocationsCount(1) barrierCount(2) -> !VPURegMapped.Index<0:0:0>
    return %arg1 : memref<1x1x1x1000xf16>
  }
}

//CHECK: %[[VAL0:.*]] = VPURT.DeclareBuffer
//CHECK: %[[VAL1:.*]] = VPURT.DeclareBuffer
//CHECK: %[[VAL2:.*]] = VPUMI37XX.ConfigureBarrier
//CHECK: %[[VAL3:.*]] = VPUMI37XX.ConfigureBarrier
//CHECK: %[[VAL5:.*]] = VPUMI37XX.DeclareKernelText
//CHECK: %[[VAL6:.*]] = VPUMI37XX.DeclareKernelArgs
//CHECK: %[[VAL7:.*]] = VPUMI37XX.DeclareKernelEntry
//CHECK: %[[VAL8:.*]] = VPUMI37XX.ActKernelRange
//CHECK: %[[VAL10:.*]] = VPUMI37XX.KernelParams
//CHECK: %[[VAL9:.*]] = VPUMI37XX.ActKernelInvocation

//CHECK-DAG: %[[VAL24:.*]] = VPURT.DeclareBuffer <DDR>
//CHECK-NEXT: %[[VAL25:.*]] = ELFNPU37XX.CreateLogicalSection {{.*}} {secAddrAlign = 1024 : i64, secInfo = 0 : i64, secName = ".bss.actKernelRtConfigSec"} -> !ELFNPU37XX.Section {
//CHECK-NEXT: ELFNPU37XX.PutOpInSection %[[VAL24]] : memref
//CHECK: %[[VAL26:.*]]  = ELFNPU37XX.Symbol %[[VAL25]] name("sym_actKernelRtConfigsSec") : !ELFNPU37XX.Section

//CHECK-DAG: %[[KERNELTEXT:.*]] = ELFNPU37XX.CreateSection {{.*}} secName = ".text.KernelText"
//CHECK-NEXT: ELFNPU37XX.PutOpInSection %[[VAL5]] : !VPURegMapped.Index<0:0:0>

//CHECK-DAG: %[[KERNELDATA:.*]] = ELFNPU37XX.CreateSection {{.*}} secName = ".text.KernelData"
//CHECK-NEXT: ELFNPU37XX.PutOpInSection %[[VAL6]] : !VPURegMapped.Index<0:0:0>

//CHECK-DAG: %[[KERNELPARAMS:.*]] = ELFNPU37XX.CreateSection {{.*}} secName = ".text.KernelParams"
//CHECK-NEXT: ELFNPU37XX.PutOpInSection %[[VAL10]] : !VPURegMapped.Index<0:0:0>

//CHECK-DAG: %[[ACTKERNELR:.*]] = ELFNPU37XX.CreateSection {{.*}} secName = ".text.ActKernelRanges"
//CHECK-NEXT: ELFNPU37XX.PutOpInSection %[[VAL8]] : !VPURegMapped.Index<0:0:0>

//CHECK-DAG: %[[ACTKERNELI:.*]] = ELFNPU37XX.CreateSection {{.*}} secName = ".text.ActKernelInvocations"
//CHECK-NEXT: ELFNPU37XX.PutOpInSection %[[VAL9]] : !VPURegMapped.Index<0:0:0>

//CHECK: %[[BUILTIN_SYMTABSEC:.*]] = ELFNPU37XX.CreateSymbolTableSection secName("VPU_RT_SYMTAB")
//CHECK: %[[SYMTABSEC:.*]] = ELFNPU37XX.CreateSymbolTableSection secName(".symtab.tasks")

//CHECK: ELFNPU37XX.CreateRelocationSection secName(".rlt.text.KernelParams") sourceSymbolTableSection(%[[SYMTABSEC]])
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL10]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL10]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL10]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL10]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>

//CHECK: ELFNPU37XX.CreateRelocationSection secName(".rlt.text.KernelParams") sourceSymbolTableSection(%[[BUILTIN_SYMTABSEC]])
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL10]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL10]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>

//CHECK: ELFNPU37XX.CreateRelocationSection secName(".rlt.text.ActKernelRanges") sourceSymbolTableSection(%[[SYMTABSEC]])
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL8]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>

//CHECK: ELFNPU37XX.CreateRelocationSection secName(".rlt.text.ActKernelInvocations") sourceSymbolTableSection(%[[BUILTIN_SYMTABSEC]])
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL9]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32_RTM>

//CHECK: ELFNPU37XX.CreateRelocationSection secName(".rlt.text.ActKernelInvocations") sourceSymbolTableSection(%[[SYMTABSEC]])
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL9]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>
//CHECK-DAG ELFNPU37XX.Reloc baseOp(%[[VAL9]] : !VPURegMapped.Index<0:0:0>) {{.*}} <R_VPU_32>
