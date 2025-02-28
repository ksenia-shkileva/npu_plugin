//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include <cstring>
#include <vpux_elf/types/vpu_extensions.hpp>
#include <vpux_elf/writer.hpp>
#include "vpux/compiler/NPU40XX/dialect/NPUReg40XX/ops.hpp"
#include "vpux/compiler/utils/ELF/utils.hpp"

#include <npu_40xx_nnrt.hpp>

using namespace vpux;
using MIVersionNote = elf::elf_note::VersionNote;

void vpux::NPUReg40XX::MappedInferenceVersionOp::serialize(elf::writer::BinaryDataSection<uint8_t>& binDataSection) {
    MIVersionNote MIVersionStruct;
    constexpr uint8_t nameSize = 4;
    constexpr uint8_t descSize = 16;
    MIVersionStruct.n_namesz = nameSize;
    MIVersionStruct.n_descz = descSize;
    MIVersionStruct.n_type = elf::elf_note::NT_NPU_MPI_VERSION;

    // As we don't have the readelf constraints of standard NOTE section types, we can here choose custom names for the
    // notes
    constexpr uint8_t name[nameSize] = {0x4d, 0x49, 0x56, 0};  // 'M'(apped) 'I'(nference) 'V'(ersion) '\0'
    static_assert(sizeof(name) == 4);
    std::memcpy(MIVersionStruct.n_name, name, nameSize);

    constexpr uint32_t desc[descSize] = {elf::elf_note::ELF_NOTE_OS_LINUX, VPU_NNRT_40XX_API_VER_MAJOR,
                                         VPU_NNRT_40XX_API_VER_MINOR, VPU_NNRT_40XX_API_VER_PATCH};
    static_assert(sizeof(desc) == 64);
    std::memcpy(MIVersionStruct.n_desc, desc, descSize);

    auto ptrCharTmp = reinterpret_cast<uint8_t*>(&MIVersionStruct);
    binDataSection.appendData(ptrCharTmp, getBinarySize());
}

size_t vpux::NPUReg40XX::MappedInferenceVersionOp::getBinarySize() {
    return sizeof(MIVersionNote);
}

size_t vpux::NPUReg40XX::MappedInferenceVersionOp::getAlignmentRequirements() {
    return alignof(MIVersionNote);
}

vpux::ELF::SectionFlagsAttr vpux::NPUReg40XX::MappedInferenceVersionOp::getAccessingProcs(mlir::SymbolUserMap&) {
    return ELF::SectionFlagsAttr::SHF_NONE;
}

vpux::ELF::SectionFlagsAttr vpux::NPUReg40XX::MappedInferenceVersionOp::getUserProcs() {
    return ELF::SectionFlagsAttr::SHF_NONE;
}

std::optional<ELF::SectionSignature> vpux::NPUReg40XX::MappedInferenceVersionOp::getSectionSignature() {
    return ELF::SectionSignature(vpux::ELF::generateSignature("note", "MappedInferenceVersion"),
                                 ELF::SectionFlagsAttr::SHF_NONE, ELF::SectionTypeAttr::SHT_NOTE);
}

bool vpux::NPUReg40XX::MappedInferenceVersionOp::hasMemoryFootprint() {
    return true;
}

void vpux::NPUReg40XX::MappedInferenceVersionOp::build(mlir::OpBuilder& builder, mlir::OperationState& state) {
    build(builder, state, "MappedInferenceVersion", VPU_NNRT_40XX_API_VER_MAJOR, VPU_NNRT_40XX_API_VER_MINOR,
          VPU_NNRT_40XX_API_VER_PATCH);
}
