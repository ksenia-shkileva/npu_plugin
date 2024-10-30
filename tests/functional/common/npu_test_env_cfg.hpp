//
// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: Apache-2.0
//

#pragma once

#include "base/ov_behavior_test_utils.hpp"
#include "common/utils.hpp"

#include <gtest/gtest.h>
#include <openvino/runtime/device_id_parser.hpp>
#include <string>

using namespace ov::test::behavior;

namespace ov::test::utils {

/**
 * Reads configuration environment variables
 */
class VpuTestEnvConfig {
public:
    std::string IE_NPU_TESTS_DEVICE_NAME;
    std::string IE_NPU_TESTS_DUMP_PATH;
    std::string IE_NPU_TESTS_LOG_LEVEL;
    std::string IE_NPU_TESTS_PLATFORM;

    bool IE_NPU_TESTS_RUN_COMPILER = true;
    bool IE_NPU_TESTS_RUN_EXPORT = false;
    bool IE_NPU_TESTS_RUN_IMPORT = false;
    bool IE_NPU_TESTS_RUN_INFER = true;
    bool IE_NPU_TESTS_EXPORT_INPUT = false;
    bool IE_NPU_TESTS_EXPORT_OUTPUT = false;
    bool IE_NPU_TESTS_EXPORT_REF = false;
    bool IE_NPU_TESTS_IMPORT_INPUT = false;
    bool IE_NPU_TESTS_IMPORT_REF = false;
    bool IE_NPU_SINGLE_CLUSTER_MODE = false;

    bool IE_NPU_TESTS_RAW_EXPORT = false;
    bool IE_NPU_TESTS_LONG_FILE_NAME = false;

public:
    static const VpuTestEnvConfig& getInstance();

private:
    explicit VpuTestEnvConfig();
};

std::string getTestsDeviceNameFromEnvironmentOr(const std::string& instead);
std::string getTestsPlatformFromEnvironmentOr(const std::string& instead);
std::string getTestsPlatformCompilerInPlugin();

std::string getDeviceNameTestCase(const std::string& str);
std::string getDeviceName();
std::string getDeviceNameID(const std::string& str);

// Current version of gtest seems to fail when parsing template functions for getTestCaseName
// To overcome this issue, programmer must make sure to wrap in paratheses this function when
// it is given at INSTANTIATE_TEST_SUITE_P macros
// e.g. INSTANTIATE_TEST_SUITE_P(TEST_SUITE_NAME, TEST_SUITE_CLASS, params,
// (appendPlatformTypeTestName<TEST_SUITE_CLASS>))
template <typename T>
std::string appendPlatformTypeTestName(testing::TestParamInfo<typename T::ParamType> obj) {
    const std::string& test_name = GenericTestCaseNameClass::getTestCaseName<T>(obj);
    return test_name + "_targetPlatform=" + getTestsPlatformFromEnvironmentOr(ov::test::utils::DEVICE_NPU);
}

}  // namespace ov::test::utils

namespace LayerTestsUtils {
using ov::test::utils::getDeviceName;
using ov::test::utils::getDeviceNameID;
using ov::test::utils::getDeviceNameTestCase;
using ov::test::utils::getTestsDeviceNameFromEnvironmentOr;
using ov::test::utils::getTestsPlatformCompilerInPlugin;
using ov::test::utils::getTestsPlatformFromEnvironmentOr;
using ov::test::utils::VpuTestEnvConfig;
}  // namespace LayerTestsUtils

namespace InferRequestParamsAnyMapTestName {
static std::string getTestCaseName(testing::TestParamInfo<ov::test::behavior::InferRequestParams> obj) {
    std::string targetDevice;
    ov::AnyMap configuration;
    std::tie(targetDevice, configuration) = obj.param;
    std::replace(targetDevice.begin(), targetDevice.end(), ':', '.');
    targetDevice = LayerTestsUtils::getTestsPlatformFromEnvironmentOr(ov::test::utils::DEVICE_NPU);
    std::ostringstream result;
    result << "targetDevice=" << targetDevice << "_";
    if (!configuration.empty()) {
        for (auto& configItem : configuration) {
            result << "configItem=" << configItem.first << "_";
            configItem.second.print(result);
            result << "_";
        }
    }
    return result.str();
}
}  // namespace InferRequestParamsAnyMapTestName

namespace InferRequestParamsMapTestName {
typedef std::tuple<std::string,                        // Device name
                   std::map<std::string, std::string>  // Config
                   >
        InferRequestParams;
static std::string getTestCaseName(testing::TestParamInfo<InferRequestParams> obj) {
    std::string targetDevice;
    std::map<std::string, std::string> configuration;
    std::tie(targetDevice, configuration) = obj.param;
    std::replace(targetDevice.begin(), targetDevice.end(), ':', '.');
    targetDevice = LayerTestsUtils::getTestsPlatformFromEnvironmentOr(ov::test::utils::DEVICE_NPU);
    std::ostringstream result;
    result << "targetDevice=" << targetDevice << "_";
    if (!configuration.empty()) {
        for (auto& configItem : configuration) {
            result << "configItem=" << configItem.first << "_" << configItem.second << "_";
        }
    }
    return result.str();
}
}  // namespace InferRequestParamsMapTestName
