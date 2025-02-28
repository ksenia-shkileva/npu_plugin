#
# Copyright (C) 2022-2023 Intel Corporation.
# SPDX-License-Identifier: Apache 2.0
#

#
# Project properties
#

set(CMAKE_POLICY_DEFAULT_CMP0115 NEW)
set(CMAKE_POLICY_DEFAULT_CMP0116 OLD)

if(ENABLE_PREBUILT_LLVM_MLIR_LIBS)
    cmake_minimum_required(VERSION 3.13 FATAL_ERROR)
else()
    # LLVM17 requires CMake >= 3.20 so the users wishing to build the LLVM from
    # sources have to upgrade accordingly.
    cmake_minimum_required(VERSION 3.20 FATAL_ERROR)
endif()

# Honor <LANG>_VISIBILITY_PRESET for all target types (including static libraries).
cmake_policy(SET CMP0063 NEW)

# Set PROJECT_VERSION* variables by project command only.
cmake_policy(SET CMP0048 NEW)

project(InferenceEngineVPUXPlugin)

#
# Build properties
#

set(NPU_DEVICE_NAME "NPU")
string(TOLOWER "${NPU_DEVICE_NAME}" VPUX_PLUGIN_COMPONENT)
set(VPUX_INTERNAL_COMPONENT "${VPUX_PLUGIN_COMPONENT}_internal")
set(VPUX_TESTS_COMPONENT "${VPUX_PLUGIN_COMPONENT}_tests")

set(NPU_CPACK_COMPONENTS_ALL ${VPUX_PLUGIN_COMPONENT} ${VPUX_INTERNAL_COMPONENT})

set(IE_MAIN_VPUX_PLUGIN_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})

if (CMAKE_BUILD_TYPE STREQUAL "")
    message(STATUS "CMAKE_BUILD_TYPE not defined, 'Release' will be used")
    set(CMAKE_BUILD_TYPE "Release")
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CMAKE_COMPILE_PDB_OUTPUT_DIRECTORY ${IE_MAIN_VPUX_PLUGIN_BINARY_DIR})
    set(CMAKE_PDB_OUTPUT_DIRECTORY ${IE_MAIN_VPUX_PLUGIN_BINARY_DIR})
endif()

if(DEFINED ENV{THIRDPARTY_SERVER_PATH})
    set(THIRDPARTY_SERVER_PATH "$ENV{THIRDPARTY_SERVER_PATH}")
elseif(DEFINED THIRDPARTY_SERVER_PATH)
    set(THIRDPARTY_SERVER_PATH "${THIRDPARTY_SERVER_PATH}")
endif()

include(FetchContent)

# TODO remove after migration
option(ENABLE_NPU_MONO "Please turn it on if you work under `npu_mono` environment" OFF)
if (ENABLE_NPU_MONO)
    message(AUTHOR_WARNING "Experimental option ENABLE_NPU_MONO enabled")
    set (NPU_MONO_ROOT ${IE_MAIN_VPUX_PLUGIN_SOURCE_DIR}/..)
endif()

find_package(OpenVINODeveloperPackage REQUIRED)

get_directory_property(defs DIRECTORY ${CMAKE_SOURCE_DIR} COMPILE_DEFINITIONS)
set(OV_BUILD_POSTFIX_VAR)
foreach(def ${defs})
    if(def MATCHES "OV_BUILD_POSTFIX=")
        string(REPLACE OV_BUILD_POSTFIX= "" OV_BUILD_POSTFIX_VAR ${def})
        remove_definitions(-D${def})
    endif()
endforeach()

include(cmake/features.cmake)
include(cmake/compile_options.cmake)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/dependencies.cmake")
    include(cmake/dependencies.cmake)
endif()

include(cmake/cross_compilation.cmake)
include(cmake/flatbuffers.cmake)
include(cmake/bundle_static_library.cmake)
include(cmake/embed_bin_file.cmake)
include(cmake/add_tool_target.cmake)
include(cmake/coverage.cmake)

if(ENABLE_PRIVATE_TESTS)
    enable_testing()
endif()

print_enabled_kmb_features()

#
# Build configuration
#

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(UNIX)
    ov_add_compiler_flags(-Wno-undef)
endif()

if(ENABLE_EXPORT_SYMBOLS)
    replace_compile_visibility_options()
endif()

if (ENABLE_SPLIT_DWARF)
    enable_split_dwarf()
endif()

#
# Sub-directories
#
if(ENABLE_PREBUILT_LLVM_MLIR_LIBS)
    message(STATUS "Include LLVM by pre-built binary")
    # Include MLIRConfig.cmake dir of pre-built binary
    # LLVM_ENABLE_RTTI should be enabled for MLIR
    list(APPEND CMAKE_PREFIX_PATH ${MLIR_BINARY_PKG_DIR}/lib/cmake/mlir)
else()
    message(STATUS "Include LLVM by source files")
    # When vpux-plugin is built independently, MLIRConfig.cmake is under this dir
    list(APPEND CMAKE_PREFIX_PATH ${PROJECT_BINARY_DIR}/lib/cmake/mlir)
    # When vpux-plugin is added as OPENVINO_EXTRA_MODULES, MLIRConfig.cmake is under this dir
    list(APPEND CMAKE_PREFIX_PATH ${OpenVINO_BINARY_DIR}/lib/cmake/mlir)
    # When vpux-plugin is added in monorepo, MLIRConfig.cmake is under this dir
    if(ENABLE_NPU_MONO)
        if(NOT DEFINED NPU_MONO_BUILD_DIR)
            message(FATAL_ERROR "Cannot find `npu_mono` build directory")
        endif()
        list(APPEND CMAKE_PREFIX_PATH ${NPU_MONO_BUILD_DIR}/lib/cmake/mlir)
    endif()
endif()

add_subdirectory(thirdparty EXCLUDE_FROM_ALL)

set(VPUNN_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/vpucostmodel")
set(VPUNN_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/thirdparty/vpucostmodel")

set(VPUNN_INCLUDE_DIRS
        "${VPUNN_SOURCE_DIR}/include"
        "${VPUNN_BINARY_DIR}/include"
)

if(ENABLE_DEVELOPER_BUILD)
    add_compile_definitions(VPUX_DEVELOPER_BUILD)
endif()

if(ENABLE_MLIR_COMPILER)
    add_subdirectory(sw_runtime_kernels/kernels)
endif()

add_subdirectory(src)

if(ENABLE_PRIVATE_TESTS)
    include(cmake/lit_tests.cmake)
    add_subdirectory(tests)
endif()

add_subdirectory(tools)

#
# targets install
#

if(ENABLE_SOURCE_PACKAGE)
    include(cmake/source_package.cmake)
endif()

if(CMAKE_SOURCE_DIR STREQUAL OpenVINO_SOURCE_DIR)
    # NPU plugin public headers should be a part of common OpenVINO headers
    set(dev_component ${OV_CPACK_COMP_CORE_DEV})
else()
    # compatibility mode while NPU plugin is not part of OpenVINO repository and can be built separately
    set(dev_component ${VPUX_PLUGIN_COMPONENT})
endif()

#
# CPack
#

ov_cpack(${NPU_CPACK_COMPONENTS_ALL})
