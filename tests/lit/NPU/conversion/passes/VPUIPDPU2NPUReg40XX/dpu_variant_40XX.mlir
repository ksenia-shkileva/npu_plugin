//
// Copyright (C) 2022-2023 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

// RUN: vpux-opt --split-input-file --init-compiler="vpu-arch=%arch%" --convert-VPUIPDPU-to-NPUReg40XX %s | FileCheck %s
// REQUIRES: arch-NPU40XX

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @Test {
    IE.CNNNetwork entryPoint : @main inputsInfo : {
        DataInfo "input_0" : tensor<1x16x16x16xf16>
        DataInfo "input_1" : tensor<16x1x1x1xi64>
    } outputsInfo : {
        DataInfo "output_0" : tensor<1x16x64x64xf16>
    }
    func.func @main() {
        ELF.Main @ELFMain {
            ELF.CreateLogicalSection @builtin.data.nncmx0 aligned(64) secType(SHT_NOBITS) secFlags(SHF_ALLOC) {
                VPUASM.DeclareBuffer @DeclareBuffer_ActIn !VPUASM.Buffer< "CMX_NN"[0] <196736> : memref<1x16x16x16xf16, #NHWC, [@CMX_NN, 0]> :  swizzling(0)>
                VPUASM.DeclareBuffer @DeclareBuffer_ActOut !VPUASM.Buffer< "CMX_NN"[0] <128> : memref<1x16x64x64xf16, #NHWC, [@CMX_NN, 0]> :  swizzling(0)>
            }
            ELF.CreateLogicalSection @builtin.tasks.DPUVariant0 aligned(64) secType(SHT_NOBITS) secFlags(SHF_ALLOC) {
                VPUASM.DeclareTaskBuffer @DeclareTaskBuffer_DPUVariant_0 idx(!VPURegMapped.Index<0:0:0>) <DPUVariant>
            }
            ELF.CreateLogicalSection @builtin.tasks.DPUInvariant0 aligned(64) secType(SHT_NOBITS) secFlags(SHF_ALLOC) {
                VPUASM.DeclareTaskBuffer @DeclareTaskBuffer_DPUInvariant_0 idx(!VPURegMapped.Index<0:0:0>) <DPUInvariant>
            }
            ELF.CreateSection @text.invariants aligned(64) secType(SHT_PROGBITS) secFlags(SHF_ALLOC) {
                VPUIPDPU.DPUInvariant @DPUInvariant_0 {task_index = !VPURegMapped.Index<0:0:0>, task_location = @builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0, input = @builtin.data.nncmx0::@DeclareBuffer_ActIn, output = @builtin.data.nncmx0::@DeclareBuffer_ActOut, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>, mpe_frequent_mode = #VPU.mpe_mode<CUBOID_16x16>, start_after = 0 : ui64, clean_after = 0 : ui64}
                    DPUCfg : {
                    ^bb0(%act_in: memref<1x16x16x16xf16, #NHWC, [@CMX_NN, 0]>,
                        %act_out: memref<1x16x64x64xf16, #NHWC, [@CMX_NN, 0]>,
                        %sparse_out: memref<1x16x64x64xi1, #NHWC, [@CMX_NN, 0]>):
                    VPUIPDPU.IDUCfg {
                        VPUIPDPU.IDUInActivations in_activations(%act_in: memref<1x16x16x16xf16, #NHWC, [@CMX_NN, 0]>)
                    }
                    VPUIPDPU.PPECfg {
                        VPUIPDPU.PPEFpAddMultBypass bypass_mode(ON)
                    }
                    VPUIPDPU.ODUCfg {
                        VPUIPDPU.ODUOutTensorSize dim_x(64) dim_y(64) dim_z(16)
                        VPUIPDPU.ODUSparsity %sparse_out: memref<1x16x64x64xi1, #NHWC, [@CMX_NN, 0]>
                        VPUIPDPU.ODUOutActivations out_activations(%act_out: memref<1x16x64x64xf16, #NHWC, [@CMX_NN, 0]>) data_width(ODU_DTYPE_16BIT)
                    }
                }
            }
            ELF.CreateSection @text.variants aligned(64) secType(SHT_PROGBITS) secFlags(SHF_ALLOC) {
                VPUIPDPU.DPUVariant @DPUVariant11 invariant(@builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0) {task_index = !VPURegMapped.Index<0:0:0>, taskLocation = @builtin.tasks.DPUVariant0::@DeclareTaskBuffer_DPUVariant_0, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>}
                DPUCfg: {
                // CHECK-NOT:   VPUIPDPU.DPUVariant
                // CHECK:       NPUReg40XX.DPUVariant
                    VPUIPDPU.IDUPadding pad_count(<left = 4, right = 6, top = 3, bottom = 5>)
                    VPUIPDPU.IDUWorkloadSet start_x(3) start_y(4) start_z(5) size_x(32) size_y(33) size_z(34)
                    VPUIPDPU.IDUNthwNtk nthw_ntk(NTHW_NTK_8_8)
                    VPUIPDPU.IDUBinaryConfig
                    VPUIPDPU.IDUConvContinue
                    VPUIPDPU.IDUSEDense
                    VPUIPDPU.IDUActSwizzle swizzle_key(SWIZZLE_KEY_1)
                    VPUIPDPU.IDUWeightSwizzle wt_swizzle_key(SWIZZLE_KEY_2)

                    // CHECK-DAG:  UINT workload_size_x at 0 size 14 = 0x20,
                    // CHECK-DAG:  UINT workload_size_y at 14 size 14 = 0x21
                    // CHECK-DAG:  UINT pad_count_up at 14 size 3 = 3,
                    // CHECK-DAG:  UINT pad_count_left at 17 size 3 = 4,
                    // CHECK-DAG:  UINT pad_count_down at 20 size 3 = 5,
                    // CHECK-DAG:  UINT pad_count_right at 23 size 3 = 6
                    // CHECK-DAG:  UINT workload_start_x at 0 size 14 = 3,
                    // CHECK-DAG:  UINT workload_start_y at 14 size 14 = 4
                    // CHECK-DAG:  UINT nthw_ntk at 0 size 2 = 0,
                    // CHECK-DAG:  UINT bin_cfg at 2 size 1 = 1,
                    // CHECK-DAG:  UINT conv_cond at 3 size 1 = 1,
                    // CHECK-DAG:  UINT dense_se at 4 size 1 = 1,
                    // CHECK-DAG:  UINT swizzle_key_offset at 6 size 3 = 1,
                    // CHECK-DAG:  UINT wt_swizzle_key at 27 size 3 = 2,
                    // CHECK-DAG:  UINT wt_swizzle_sel at 30 size 1 = 1

                    VPUIPDPU.BarrierCfg waits([1 : ui8, 2 : ui8]) updates([3 : ui8, 4 : ui8, 5 : ui8]) start_after(0) clean_after(0)
                    // CHECK-DAG:  cbarrier_lo offset 32 size 64 = UINT 6,
                    // CHECK-DAG:  UINT cbarrier_hi at 0 size 32 = 0
                    // CHECK-DAG:  pbarrier_lo offset 48 size 64 = UINT 0x38,
                    // CHECK-DAG:  UINT pbarrier_hi at 0 size 32 = 0

                    VPUIPDPU.ODUHaloRegion begin_coord_x(0) begin_coord_y(0) end_coord_x(15) end_coord_y(15) activations_offset(10) sparsity_offset(10) target_width(32) cast_to_tile("DPU_TILE_1|DPU_TILE_2")
                    // CHECK-DAG:  halo_region0A
                    // CHECK-DAG:  SINT sp_adr_offset at 0 size 22 = 0xA,
                    // CHECK-DAG:  UINT tile_select at 22 size 7 = 6,
                    // CHECK-DAG:  UINT enable at 31 size 1 = 1
                    // CHECK-DAG:  halo_region0B
                    // CHECK-DAG:  SINT ac_adr_offset at 0 size 22 = 0xA,
                    // CHECK-DAG:  UINT target_width_lsb at 22 size 10 = 0x20
                    // CHECK-DAG:  halo_region0C
                    // CHECK-DAG:  UINT begin_x at 0 size 13 = 0,
                    // CHECK-DAG:  UINT begin_y at 13 size 13 = 0,
                    // CHECK-DAG:  UINT target_width_msb at 26 size 4 = 0
                    // CHECK-DAG:  halo_region0D
                    // CHECK-DAG:  UINT end_x at 0 size 13 = 0xF,
                    // CHECK-DAG:  UINT end_y at 13 size 13 = 0xF,

                    VPUIPDPU.ODUHaloRegion begin_coord_x(4) begin_coord_y(5) end_coord_x(15) end_coord_y(16) activations_offset(9) target_width(64) cast_to_tile("DPU_TILE_1|DPU_TILE_3")
                    // CHECK-DAG:  halo_region1A
                    // CHECK-DAG:  SINT sp_adr_offset at 0 size 22 = 0,
                    // CHECK-DAG:  UINT tile_select at 22 size 7 = 0xA,
                    // CHECK-DAG:  UINT enable at 31 size 1 = 1
                    // CHECK-DAG:  halo_region1B
                    // CHECK-DAG:  SINT ac_adr_offset at 0 size 22 = 9,
                    // CHECK-DAG:  UINT target_width_lsb at 22 size 10 = 0x40
                    // CHECK-DAG:  halo_region1C
                    // CHECK-DAG:  UINT begin_x at 0 size 13 = 4,
                    // CHECK-DAG:  UINT begin_y at 13 size 13 = 5,
                    // CHECK-DAG:  UINT target_width_msb at 26 size 4 = 0
                    // CHECK-DAG:  halo_region1D
                    // CHECK-DAG:  UINT end_x at 0 size 13 = 0xF,
                    // CHECK-DAG:  UINT end_y at 13 size 13 = 0x10,

                    VPUIPDPU.ODUHaloRegion begin_coord_x(9) begin_coord_y(0) end_coord_x(63) end_coord_y(63) activations_offset(400) target_width(15424) cast_to_tile("DPU_TILE_0|DPU_TILE_1|DPU_TILE_2|DPU_TILE_3|DPU_TILE_4|DPU_TILE_5")
                    // CHECK-DAG:  halo_region2A
                    // CHECK-DAG:  SINT sp_adr_offset at 0 size 22 = 0,
                    // CHECK-DAG:  UINT tile_select at 22 size 7 = 0x3F,
                    // CHECK-DAG:  UINT enable at 31 size 1 = 1
                    // CHECK-DAG:  halo_region2B
                    // CHECK-DAG:  SINT ac_adr_offset at 0 size 22 = 0x190,
                    // CHECK-DAG:  UINT target_width_lsb at 22 size 10 = 0x40
                    // CHECK-DAG:  halo_region2C
                    // CHECK-DAG:  UINT begin_x at 0 size 13 = 9,
                    // CHECK-DAG:  UINT begin_y at 13 size 13 = 0,
                    // CHECK-DAG:  UINT target_width_msb at 26 size 4 = 0xF
                    // CHECK-DAG:  halo_region2D
                    // CHECK-DAG:  UINT end_x at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT end_y at 13 size 13 = 0x3F,

                    VPUIPDPU.ODUHaloRegion begin_coord_x(9) begin_coord_y(0) end_coord_x(63) end_coord_y(63) activations_offset(9) target_width(15488) cast_to_tile("DPU_TILE_0|DPU_TILE_5")
                    // CHECK-DAG:  halo_region3A
                    // CHECK-DAG:  SINT sp_adr_offset at 0 size 22 = 0,
                    // CHECK-DAG:  UINT tile_select at 22 size 7 = 0x21,
                    // CHECK-DAG:  UINT enable at 31 size 1 = 1
                    // CHECK-DAG:  halo_region3B
                    // CHECK-DAG:  SINT ac_adr_offset at 0 size 22 = 9,
                    // CHECK-DAG:  UINT target_width_lsb at 22 size 10 = 0x80
                    // CHECK-DAG:  halo_region3C
                    // CHECK-DAG:  UINT begin_x at 0 size 13 = 9,
                    // CHECK-DAG:  UINT begin_y at 13 size 13 = 0,
                    // CHECK-DAG:  UINT target_width_msb at 26 size 4 = 0xF
                    // CHECK-DAG:  halo_region3D
                    // CHECK-DAG:  UINT end_x at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT end_y at 13 size 13 = 0x3F,

                    VPUIPDPU.ODUHaloRegion begin_coord_x(9) begin_coord_y(0) end_coord_x(63) end_coord_y(63) activations_offset(9) target_width(3328) cast_to_tile("DPU_TILE_2")
                    // CHECK-DAG:  halo_region4A
                    // CHECK-DAG:  SINT sp_adr_offset at 0 size 22 = 0,
                    // CHECK-DAG:  UINT tile_select at 22 size 7 = 4,
                    // CHECK-DAG:  UINT enable at 31 size 1 = 1
                    // CHECK-DAG:  halo_region4B
                    // CHECK-DAG:  SINT ac_adr_offset at 0 size 22 = 9,
                    // CHECK-DAG:  UINT target_width_lsb at 22 size 10 = 0x100
                    // CHECK-DAG:  halo_region4C
                    // CHECK-DAG:  UINT begin_x at 0 size 13 = 9,
                    // CHECK-DAG:  UINT begin_y at 13 size 13 = 0,
                    // CHECK-DAG:  UINT target_width_msb at 26 size 4 = 3
                    // CHECK-DAG:  halo_region4D
                    // CHECK-DAG:  UINT end_x at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT end_y at 13 size 13 = 0x3F,

                    VPUIPDPU.ODUOutSubtensor begin_coord_x(1) begin_coord_y(32) begin_coord_z(64) end_coord_x(63) end_coord_y(63) end_coord_z(15)
                    // CHECK-DAG:  UINT te_beg_y at 0 size 13 = 0x20,
                    // CHECK-DAG:  UINT te_beg_z at 13 size 13 = 0x40
                    // CHECK-DAG:  UINT te_beg_x at 0 size 13 = 1
                    // CHECK-DAG:  UINT te_end_y at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT te_end_z at 13 size 13 = 0xF
                    // CHECK-DAG:  UINT te_end_x at 0 size 13 = 0x3F
                    VPUIPDPU.DPUGroup invariantIdx(!VPURegMapped.Index<0:0:0>) variantCount(4) {isFirstVariant}
                    // CHECK-DAG:  UINT invar_lptr_force at 14 size 1 = 1,
                    // CHECK-DAG:  UINT workload_odu_auto_upd at 8 size 1 = 0,
                    // CHECK-DAG:  invariant_index_ offset 200 size 32 = UINT 0,
                }

                VPUIPDPU.DPUVariant @DPUVariant22 invariant(@builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0) {task_index = !VPURegMapped.Index<0:0:0>, taskLocation = @builtin.tasks.DPUVariant0::@DeclareTaskBuffer_DPUVariant_0, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>}
                DPUCfg: {
                // CHECK-NOT:   VPUIPDPU.DPUVariant
                // CHECK:       NPUReg40XX.DPUVariant
                    VPUIPDPU.IDUPadding pad_count(<left = 4, right = 6, top = 3, bottom = 5>)
                    VPUIPDPU.IDUWorkloadSet start_x(3) start_y(4) start_z(5) size_x(32) size_y(33) size_z(34)
                    VPUIPDPU.IDUNthwNtk nthw_ntk(NTHW_NTK_4_16)
                    VPUIPDPU.IDUActSwizzle swizzle_key(SWIZZLE_KEY_3)

                    // CHECK-DAG:  UINT workload_size_x at 0 size 14 = 0x20,
                    // CHECK-DAG:  UINT workload_size_y at 14 size 14 = 0x21
                    // CHECK-DAG:  UINT pad_count_up at 14 size 3 = 3,
                    // CHECK-DAG:  UINT pad_count_left at 17 size 3 = 4,
                    // CHECK-DAG:  UINT pad_count_down at 20 size 3 = 5,
                    // CHECK-DAG:  UINT pad_count_right at 23 size 3 = 6
                    // CHECK-DAG:  UINT workload_start_x at 0 size 14 = 3,
                    // CHECK-DAG:  UINT workload_start_y at 14 size 14 = 4
                    // CHECK-DAG:  UINT nthw_ntk at 0 size 2 = 1,
                    // CHECK-DAG:  UINT bin_cfg at 2 size 1 = 0,
                    // CHECK-DAG:  UINT conv_cond at 3 size 1 = 0,
                    // CHECK-DAG:  UINT dense_se at 4 size 1 = 0,
                    // CHECK-DAG:  UINT swizzle_key_offset at 6 size 3 = 3,
                    // CHECK-DAG:  UINT wt_swizzle_key at 27 size 3 = 0,
                    // CHECK-DAG:  UINT wt_swizzle_sel at 30 size 1 = 1

                    VPUIPDPU.ODUOutSubtensor begin_coord_x(0) begin_coord_y(0) begin_coord_z(0) end_coord_x(63) end_coord_y(63) end_coord_z(15)
                    // CHECK-DAG:  UINT te_beg_y at 0 size 13 = 0,
                    // CHECK-DAG:  UINT te_beg_z at 13 size 13 = 0
                    // CHECK-DAG:  UINT te_beg_x at 0 size 13 = 0
                    // CHECK-DAG:  UINT te_end_y at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT te_end_z at 13 size 13 = 0xF
                    // CHECK-DAG:  UINT te_end_x at 0 size 13 = 0x3F
                    VPUIPDPU.DPUGroup invariantIdx(!VPURegMapped.Index<0:0:0>) variantCount(4)
                    // CHECK-DAG:  UINT invar_lptr_force at 14 size 1 = 0,
                    // CHECK-DAG:  UINT workload_odu_auto_upd at 8 size 1 = 0,
                    // CHECK-DAG:  invariant_index_ offset 200 size 32 = UINT 0,
                }

                VPUIPDPU.DPUVariant @DPUVariant33 invariant(@builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0) {task_index = !VPURegMapped.Index<0:0:0>, taskLocation = @builtin.tasks.DPUVariant0::@DeclareTaskBuffer_DPUVariant_0, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>}
                DPUCfg: {
                // CHECK-NOT:   VPUIPDPU.DPUVariant
                // CHECK:       NPUReg40XX.DPUVariant
                    ^bb0(%weights_tensor: memref<32x16x3x3xf16, #NHWC, [@CMX_NN, 0]>):

                    VPUIPDPU.IDUNthwNtk nthw_ntk(NTHW_NTK_16_4)
                    VPUIPDPU.IDUActSwizzle swizzle_key(SWIZZLE_KEY_4)
                    // CHECK-DAG:  UINT nthw_ntk at 0 size 2 = 3,
                    // CHECK-DAG:  UINT swizzle_key_offset at 6 size 3 = 4,

                    VPUIPDPU.ODUOutSubtensor begin_coord_x(0) begin_coord_y(5) begin_coord_z(4) end_coord_x(63) end_coord_y(63) end_coord_z(15)
                    // CHECK-DAG:  UINT te_beg_y at 0 size 13 = 5,
                    // CHECK-DAG:  UINT te_beg_z at 13 size 13 = 4
                    // CHECK-DAG:  UINT te_beg_x at 0 size 13 = 0
                    // CHECK-DAG:  UINT te_end_y at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT te_end_z at 13 size 13 = 0xF
                    // CHECK-DAG:  UINT te_end_x at 0 size 13 = 0x3F

                    VPUIPDPU.IDUWeightSet weight_start(0) weight_num(32) weight_size(144)
                    // CHECK-DAG:  weight_size offset 180 size 32 = UINT 0x90,
                    // CHECK-DAG:  weight_num offset 184 size 32 = UINT 0x20,
                    // CHECK-DAG:  weight_start offset 188 size 32 = UINT 0,
                    VPUIPDPU.DPUGroup invariantIdx(!VPURegMapped.Index<0:0:0>) variantCount(4)
                    // CHECK-DAG:  UINT invar_lptr_force at 14 size 1 = 0,
                    // CHECK-DAG:  UINT workload_odu_auto_upd at 8 size 1 = 0,
                    // CHECK-DAG:  invariant_index_ offset 200 size 32 = UINT 0,
                }

                // Use default initialized values
                VPUIPDPU.DPUVariant @DPUVariant44 invariant(@builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0) {task_index = !VPURegMapped.Index<0:0:0>, taskLocation = @builtin.tasks.DPUVariant0::@DeclareTaskBuffer_DPUVariant_0, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>}
                DPUCfg: {
                // CHECK-NOT:   VPUIPDPU.DPUVariant
                // CHECK:       NPUReg40XX.DPUVariant
                    ^bb0(%weights_tensor: memref<32x16x3x3xf16, #NHWC, [@CMX_NN, 0]>):
                    // CHECK-DAG:  UINT shave_l2_cache_en at 19 size 1 = 0,
                    // CHECK-DAG:  UINT workload_prm_sel at 2 size 1 = 0,
                    VPUIPDPU.ODUOutSubtensor begin_coord_x(0) begin_coord_y(0) begin_coord_z(0) end_coord_x(63) end_coord_y(63) end_coord_z(15)
                    // CHECK-DAG:  UINT te_beg_y at 0 size 13 = 0,
                    // CHECK-DAG:  UINT te_beg_z at 13 size 13 = 0
                    // CHECK-DAG:  UINT te_beg_x at 0 size 13 = 0
                    // CHECK-DAG:  UINT te_end_y at 0 size 13 = 0x3F,
                    // CHECK-DAG:  UINT te_end_z at 13 size 13 = 0xF
                    // CHECK-DAG:  UINT te_end_x at 0 size 13 = 0x3F
                    VPUIPDPU.DPUGroup invariantIdx(!VPURegMapped.Index<0:0:0>) variantCount(4) {isLastVariant}
                    // CHECK-DAG:  UINT invar_lptr_force at 14 size 1 = 0,
                    // CHECK-DAG:  UINT workload_odu_auto_upd at 8 size 1 = 1,
                    // CHECK-DAG:  invariant_index_ offset 200 size 32 = UINT 0,
                }
            }
            ELF.CreateSymbolTableSection @symtab secFlags("SHF_NONE") {
                ELF.Symbol @elfsym.builtin.data.nncmx0 of(@builtin.data.nncmx0) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.builtin.tasks.DPUVariant0 of(@builtin.tasks.DPUVariant0) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.builtin.tasks.DPUInvariant0 of(@builtin.tasks.DPUInvariant0) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.text.invariants of(@text.invariants) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.text.variants of(@text.variants) type(<STT_SECTION>) size(0) value(0)
            }
        }

        return
    }
}

// -----

#NHWC = affine_map<(d0, d1, d2, d3) -> (d0, d2, d3, d1)>
module @ProfilingTest {
    IE.CNNNetwork entryPoint : @main inputsInfo : {
        DataInfo "input_0" : tensor<1x16x16x16xf16>
        DataInfo "input_1" : tensor<16x1x1x1xi64>
    } outputsInfo : {
        DataInfo "output_0" : tensor<1x16x64x64xf16>
    } profilingOutputsInfo : {
        DataInfo "profilingOutput" : tensor<32xui32>
    }
    func.func @main() {
        ELF.Main @ELFMain {
            ELF.CreateLogicalSection @builtin.data.nncmx0 aligned(64) secType(SHT_NOBITS) secFlags(SHF_ALLOC) {
                VPUASM.DeclareBuffer @DeclareBuffer_ActIn !VPUASM.Buffer< "CMX_NN"[0] <196736> : memref<1x16x16x16xf16, #NHWC, [@CMX_NN, 0]> :  swizzling(0)>
                VPUASM.DeclareBuffer @DeclareBuffer_WeightTable !VPUASM.Buffer< "CMX_NN"[0] <0> : memref<16x1x1x1xi64, #NHWC, [@CMX_NN, 0]> :  swizzling(0)>
                VPUASM.DeclareBuffer @DeclareBuffer_ActOut !VPUASM.Buffer< "CMX_NN"[0] <128> : memref<1x16x64x64xf16, #NHWC, [@CMX_NN, 0]> :  swizzling(0)>
                VPUASM.DeclareBuffer @DeclareBuffer_ProfilingData !VPUASM.Buffer< "CMX_NN"[0] <232064> : memref<4xui64, [@CMX_NN, 0]> :  swizzling(0)>
            }
            ELF.CreateLogicalSection @builtin.tasks.DPUVariant0 aligned(64) secType(SHT_NOBITS) secFlags(SHF_ALLOC) {
                VPUASM.DeclareTaskBuffer @DeclareTaskBuffer_DPUVariant_0 idx(!VPURegMapped.Index<0:0:0>) <DPUVariant>
            }
            ELF.CreateLogicalSection @builtin.tasks.DPUInvariant0 aligned(64) secType(SHT_NOBITS) secFlags(SHF_ALLOC) {
                VPUASM.DeclareTaskBuffer @DeclareTaskBuffer_DPUInvariant_0 idx(!VPURegMapped.Index<0:0:0>) <DPUInvariant>
            }
            ELF.CreateSection @text.invariants aligned(64) secType(SHT_PROGBITS) secFlags(SHF_ALLOC) {
                VPUIPDPU.DPUInvariant @DPUInvariant_0 {task_index = !VPURegMapped.Index<0:0:0>, task_location = @builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0, input = @builtin.data.nncmx0::@DeclareBuffer_ActIn, output = @builtin.data.nncmx0::@DeclareBuffer_ActOut, profiling_data = @builtin.data.nncmx0::@DeclareBuffer_ProfilingData, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>, mpe_frequent_mode = #VPU.mpe_mode<CUBOID_16x16>, start_after = 0 : ui64, clean_after = 0 : ui64}
                    DPUCfg : {
                    ^bb0(%act_in: memref<1x16x16x16xf16, #NHWC, [@CMX_NN, 0]>,
                        %weight_table: memref<16x1x1x1xi64, #NHWC, [@CMX_NN, 0]>,
                        %act_out: memref<1x16x64x64xf16, #NHWC, [@CMX_NN, 0]>,
                        %sparse_out: memref<1x16x64x64xi1, #NHWC, [@CMX_NN, 0]>):
                    VPUIPDPU.IDUCfg {
                        VPUIPDPU.IDUInActivations in_activations(%act_in: memref<1x16x16x16xf16, #NHWC, [@CMX_NN, 0]>)
                    }
                    VPUIPDPU.PPECfg {
                        VPUIPDPU.PPEFpAddMultBypass bypass_mode(ON)
                    }
                    VPUIPDPU.ODUCfg {
                        VPUIPDPU.ODUOutTensorSize dim_x(64) dim_y(64) dim_z(16)
                        VPUIPDPU.ODUSparsity %sparse_out: memref<1x16x64x64xi1, #NHWC, [@CMX_NN, 0]>
                        VPUIPDPU.ODUOutActivations out_activations(%act_out: memref<1x16x64x64xf16, #NHWC, [@CMX_NN, 0]>) data_width(ODU_DTYPE_16BIT)
                    }
                }
            }
            ELF.CreateSection @text.variants aligned(64) secType(SHT_PROGBITS) secFlags(SHF_ALLOC) {
                VPUIPDPU.DPUVariant @DPUVariant11 invariant(@builtin.tasks.DPUInvariant0::@DeclareTaskBuffer_DPUInvariant_0) {task_index = !VPURegMapped.Index<0:0:0>, taskLocation = @builtin.tasks.DPUVariant0::@DeclareTaskBuffer_DPUVariant_0, nce_task_type = #VPUIP.nce_task_type<MAXPOOL>, workload_id = 241 : i64}
                DPUCfg: {
                // CHECK-NOT:   VPUIPDPU.DPUVariant
                // CHECK:       NPUReg40XX.DPUVariant
                    VPUIPDPU.IDUPadding pad_count(<left = 4, right = 6, top = 3, bottom = 5>)
                    VPUIPDPU.IDUWorkloadSet start_x(3) start_y(4) start_z(5) size_x(32) size_y(33) size_z(34)
                    VPUIPDPU.IDUNthwNtk nthw_ntk(NTHW_NTK_8_8)
                    VPUIPDPU.IDUBinaryConfig
                    VPUIPDPU.IDUConvContinue
                    VPUIPDPU.IDUSEDense
                    VPUIPDPU.IDUActSwizzle swizzle_key(SWIZZLE_KEY_1)
                    VPUIPDPU.IDUWeightSwizzle wt_swizzle_key(SWIZZLE_KEY_2)
                    VPUIPDPU.BarrierCfg waits([1 : ui8, 2 : ui8]) updates([3 : ui8, 4 : ui8, 5 : ui8]) start_after(0) clean_after(0)

                    VPUIPDPU.ODUHaloRegion begin_coord_x(0) begin_coord_y(0) end_coord_x(15) end_coord_y(15) activations_offset(10) sparsity_offset(10) target_width(32) cast_to_tile("DPU_TILE_1|DPU_TILE_2")
                    VPUIPDPU.ODUHaloRegion begin_coord_x(4) begin_coord_y(5) end_coord_x(15) end_coord_y(16) activations_offset(9) target_width(64) cast_to_tile("DPU_TILE_1|DPU_TILE_3")
                    VPUIPDPU.ODUHaloRegion begin_coord_x(9) begin_coord_y(0) end_coord_x(63) end_coord_y(63) activations_offset(400) target_width(15424) cast_to_tile("DPU_TILE_0|DPU_TILE_1|DPU_TILE_2|DPU_TILE_3|DPU_TILE_4|DPU_TILE_5")
                    VPUIPDPU.ODUHaloRegion begin_coord_x(9) begin_coord_y(0) end_coord_x(63) end_coord_y(63) activations_offset(9) target_width(15488) cast_to_tile("DPU_TILE_0|DPU_TILE_5")
                    VPUIPDPU.ODUHaloRegion begin_coord_x(9) begin_coord_y(0) end_coord_x(63) end_coord_y(63) activations_offset(9) target_width(3328) cast_to_tile("DPU_TILE_2")
                    VPUIPDPU.ODUOutSubtensor begin_coord_x(1) begin_coord_y(32) begin_coord_z(64) end_coord_x(63) end_coord_y(63) end_coord_z(15)

                    VPUIPDPU.DPUGroup invariantIdx(!VPURegMapped.Index<0:0:0>) variantCount(1) {isFirstVariant}
                    // CHECK-DAG:  UINT invar_lptr_force at 14 size 1 = 1,
                    // CHECK-DAG:  UINT workload_odu_auto_upd at 8 size 1 = 0,
                    // CHECK-DAG:  invariant_index_ offset 200 size 32 = UINT 0,
                }

                // CHECK-DAG:  UINT odu_stat_en at 13 size 1 = 1,
                // CHECK-DAG:  UINT idu_stat_en at 14 size 1 = 1,
                // CHECK-DAG:  UINT odu_stat_clr_mode at 16 size 1 = 0,
                // CHECK-DAG:  UINT idu_stat_clr_mode at 17 size 1 = 0,
                // CHECK-DAG:  UINT hwp_wload_id at 0 size 16 = 0xF1
            }
            ELF.CreateSymbolTableSection @symtab secFlags("SHF_NONE") {
                ELF.Symbol @elfsym.builtin.data.nncmx0 of(@builtin.data.nncmx0) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.builtin.tasks.DPUVariant0 of(@builtin.tasks.DPUVariant0) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.builtin.tasks.DPUInvariant0 of(@builtin.tasks.DPUInvariant0) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.text.invariants of(@text.invariants) type(<STT_SECTION>) size(0) value(0)
                ELF.Symbol @elfsym.text.variants of(@text.variants) type(<STT_SECTION>) size(0) value(0)
            }
        }

        return
    }
}
