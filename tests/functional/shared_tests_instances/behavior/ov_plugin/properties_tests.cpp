//
// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: Apache-2.0
//

#include "behavior/ov_plugin/properties_tests.hpp"
#include <array>
#include "common/npu_test_env_cfg.hpp"
#include "common/utils.hpp"
#include "intel_npu/al/config/common.hpp"
#include "npu_private_properties.hpp"
#include "openvino/runtime/intel_cpu/properties.hpp"
#include "openvino/runtime/intel_gpu/properties.hpp"
#include "openvino/runtime/intel_npu/properties.hpp"

namespace {

template <typename T>
constexpr std::vector<T> operator+(const std::vector<T>& vector1, const std::vector<T>& vector2) {
    std::vector<T> result;
    result.insert(std::end(result), std::begin(vector1), std::end(vector1));
    result.insert(std::end(result), std::begin(vector2), std::end(vector2));
    return result;
}

ov::log::Level getTestsLogLevelFromEnvironmentOr(ov::log::Level instead) {
    if (auto var = std::getenv("OV_NPU_LOG_LEVEL")) {
        std::istringstream stringStream = std::istringstream(var);
        ov::log::Level level;

        stringStream >> level;

        return level;
    }
    return instead;
}

const std::vector<ov::AnyMap> CorrectPluginMutableProperties = {
        // OV
        {{ov::hint::performance_mode.name(), ov::hint::PerformanceMode::THROUGHPUT}},
        {{ov::hint::execution_mode.name(), ov::hint::ExecutionMode::ACCURACY}},
        {{ov::hint::num_requests.name(), 2u}},
        {{ov::log::level.name(), ov::log::Level::ERR}},
        {{ov::device::id.name(), removeDeviceNameOnlyID(ov::test::utils::getTestsPlatformFromEnvironmentOr("3720"))}},
        {{ov::enable_profiling.name(), true}},
};

const std::vector<ov::AnyMap> driverCorrectPluginMutableProperties = {
        {{ov::intel_npu::compiler_type.name(), ov::intel_npu::CompilerType::DRIVER}},
};

const std::vector<ov::AnyMap> CorrectPluginDefaultMutableProperties = {
        /// OV
        {{ov::enable_profiling.name(), false}},
        {{ov::hint::performance_mode.name(), ov::hint::PerformanceMode::LATENCY}},
        {{ov::hint::num_requests.name(), 1u}},
        {{ov::log::level.name(), getTestsLogLevelFromEnvironmentOr(ov::log::Level::NO)}},
        {{ov::device::id.name(), ""}},
        {{ov::num_streams.name(), ov::streams::Num(1)}},
        {{ov::hint::execution_mode.name(), ov::hint::ExecutionMode::PERFORMANCE}},
};

const std::vector<std::string> ImmutableProperties = {
        ov::supported_properties.name(),
        ov::streams::num.name(),
        ov::optimal_number_of_infer_requests.name(),
        ov::intel_npu::device_alloc_mem_size.name(),
        ov::intel_npu::device_total_mem_size.name(),
        ov::intel_npu::driver_version.name(),
        ov::available_devices.name(),
        ov::device::capabilities.name(),
        ov::range_for_async_infer_requests.name(),
        ov::range_for_streams.name(),
        ov::device::uuid.name(),
        ov::device::architecture.name(),
        ov::device::full_name.name(),
        ov::device::pci_info.name(),
        ov::device::gops.name(),
        ov::device::type.name(),
};

const std::vector<ov::AnyMap> CorrectCompiledModelProperties = {
        {{ov::device::id.name(), removeDeviceNameOnlyID(ov::test::utils::getTestsPlatformFromEnvironmentOr("3720"))}},
        {{ov::enable_profiling.name(), true}},
        {{ov::hint::performance_mode.name(), ov::hint::PerformanceMode::LATENCY}},
        {{ov::hint::execution_mode.name(), ov::hint::ExecutionMode::PERFORMANCE}},
        {{ov::hint::num_requests.name(), 4u}},
        {{ov::hint::enable_cpu_pinning.name(), true}},
};

const std::vector<ov::AnyMap> IncorrectImmutableProperties = {
        {{ov::streams::num.name(), ov::streams::Num(2)}},
        {{ov::optimal_number_of_infer_requests.name(), 4}},
        {{ov::intel_npu::device_alloc_mem_size.name(), 1024}},
        {{ov::intel_npu::device_total_mem_size.name(), 2048}},
        {{ov::intel_npu::driver_version.name(), 3}},
        {{ov::available_devices.name(), testing::internal::Strings{"3720", "4000"}}},
        {{ov::device::capabilities.name(), testing::internal::Strings{ov::device::capability::BF16}}},
        {{ov::range_for_async_infer_requests.name(),
          std::tuple<unsigned int, unsigned int, unsigned int>{1u, 10u, 1u}}},
        {{ov::range_for_streams.name(), std::tuple<unsigned int, unsigned int>{1u, 4u}}},
        {{ov::device::uuid.name(),
          ov::device::UUID{std::array<uint8_t, ov::device::UUID::MAX_UUID_SIZE>{
                  0x80, 0xd1, 0xd1, 0x1e, 0xb7, 0x38, 0x11, 0xea, 0xb3, 0xde, 0x02, 0x42, 0xac, 0x13, 0x00, 0x04}}}},
        {{ov::device::architecture.name(), "4000"}},
        {{ov::device::type.name(), "NPU"}},
        {{ov::device::full_name.name(), "NPU.3720"}},
        {{ov::device::pci_info.name(),
          ov::device::PCIInfo{0xFFFF, 0xFFFF, 0, 0xFFFF}}},  // setting invalid domain,bus,device and function ids
        {{ov::device::gops.name(), std::map<ov::element::Type, float>{{ov::element::f32, 1},
                                                                      {ov::element::f16, 0},
                                                                      {ov::element::u8, 0},
                                                                      {ov::element::i8, 0}}}}};  // namespace

const std::vector<ov::AnyMap> IncorrectMutablePropertiesWrongValueTypes = {
        // OV
        {{ov::enable_profiling.name(), 'c'}},
        {{ov::hint::performance_mode.name(), ov::intel_npu::CompilerType::DRIVER}},
        {{ov::hint::execution_mode.name(), ov::hint::PerformanceMode::LATENCY}},
        {{ov::hint::num_requests.name(), -2.0f}},
        {{ov::log::level.name(), -2}},
        {{ov::device::id.name(), "false"}},
        {{ov::num_streams.name(), "one"}},
};

const std::vector<ov::AnyMap> IncorrectInexistingProperties = {
        {{ov::affinity.name(), ov::Affinity::HYBRID_AWARE}},
        {{ov::intel_cpu::denormals_optimization.name(), true}},
        {{ov::intel_gpu::hint::host_task_priority.name(), ov::hint::Priority::LOW}},
        {{ov::intel_gpu::hint::queue_throttle.name(), ov::intel_gpu::hint::ThrottleLevel::HIGH}}};

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests, OVPropertiesTests,
                         ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                                            ::testing::ValuesIn(CorrectPluginMutableProperties)),
                         (ov::test::utils::appendPlatformTypeTestName<OVPropertiesTests>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_Driver, OVSetPropComplieModleGetPropTests,
                         ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                                            ::testing::ValuesIn(driverCorrectPluginMutableProperties),
                                            ::testing::ValuesIn(CorrectCompiledModelProperties)),
                         (ov::test::utils::appendPlatformTypeTestName<OVSetPropComplieModleGetPropTests>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests, OVPropertiesIncorrectTests,
                         ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                                            ::testing::ValuesIn(IncorrectImmutableProperties +
                                                                IncorrectMutablePropertiesWrongValueTypes +
                                                                IncorrectInexistingProperties)),
                         (ov::test::utils::appendPlatformTypeTestName<OVPropertiesIncorrectTests>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests, OVPropertiesDefaultSupportedTests,
                         ::testing::Values(ov::test::utils::DEVICE_NPU),
                         (ov::test::utils::appendPlatformTypeTestName<OVPropertiesDefaultSupportedTests>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVClassCommon, OVBasicPropertiesTestsP,
                         ::testing::Values(std::make_pair("openvino_intel_npu_plugin", ov::test::utils::DEVICE_NPU)),
                         (ov::test::utils::appendPlatformTypeTestName<OVBasicPropertiesTestsP>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests, OVPropertiesDefaultTests,
                         ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                                            ::testing::ValuesIn(CorrectPluginDefaultMutableProperties)),
                         (ov::test::utils::appendPlatformTypeTestName<OVPropertiesDefaultTests>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVCheckSetSupportedRWMetricsPropsTests, OVCheckSetSupportedRWMetricsPropsTests,
        ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                           ::testing::ValuesIn(getRWMandatoryPropertiesValues(CorrectPluginMutableProperties))),
        (ov::test::utils::appendPlatformTypeTestName<OVCheckSetSupportedRWMetricsPropsTests>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVCheckSetSupportedRWMetricsPropsTests_Driver, OVCheckSetSupportedRWMetricsPropsTests,
        ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                           ::testing::ValuesIn(getRWMandatoryPropertiesValues(driverCorrectPluginMutableProperties))),
        (ov::test::utils::appendPlatformTypeTestName<OVCheckSetSupportedRWMetricsPropsTests>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVCheckGetSupportedROMetricsPropsTests, OVCheckGetSupportedROMetricsPropsTests,
        ::testing::Combine(
                ::testing::Values(ov::test::utils::DEVICE_NPU),
                ::testing::ValuesIn(OVCheckGetSupportedROMetricsPropsTests::configureProperties(ImmutableProperties))),
        (ov::test::utils::appendPlatformTypeTestName<OVCheckGetSupportedROMetricsPropsTests>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVCheckChangePropComplieModleGetPropTests_DEVICE_ID,
        OVCheckChangePropComplieModleGetPropTests_DEVICE_ID,
        ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                           ::testing::ValuesIn(CorrectCompiledModelProperties)),
        (ov::test::utils::appendPlatformTypeTestName<OVCheckChangePropComplieModleGetPropTests_DEVICE_ID>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVCheckChangePropComplieModleGetPropTests_InferencePrecision,
        OVCheckChangePropComplieModleGetPropTests_InferencePrecision,
        ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                           ::testing::ValuesIn(CorrectCompiledModelProperties)),
        (ov::test::utils::appendPlatformTypeTestName<OVCheckChangePropComplieModleGetPropTests_InferencePrecision>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVCheckMetricsPropsTests_ModelDependceProps,
                         OVCheckMetricsPropsTests_ModelDependceProps,
                         ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                                            ::testing::ValuesIn(CorrectCompiledModelProperties)),
                         (ov::test::utils::appendPlatformTypeTestName<OVCheckMetricsPropsTests_ModelDependceProps>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVClassSetDefaultDeviceIDPropTest, OVClassSetDefaultDeviceIDPropTest,
                         ::testing::Values(std::make_pair(
                                 ov::test::utils::DEVICE_NPU,
                                 removeDeviceNameOnlyID(ov::test::utils::getTestsPlatformFromEnvironmentOr("3720")))),
                         (ov::test::utils::appendPlatformTypeTestName<OVClassSetDefaultDeviceIDPropTest>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVClassSpecificDeviceTest, OVSpecificDeviceSetConfigTest,
        ::testing::Values(std::string(ov::test::utils::DEVICE_NPU) + "." +
                          removeDeviceNameOnlyID(ov::test::utils::getTestsPlatformFromEnvironmentOr("3720"))),
        (ov::test::utils::appendPlatformTypeTestName<OVSpecificDeviceSetConfigTest>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVClassSpecificDeviceTest, OVSpecificDeviceGetConfigTest,
        ::testing::Values(std::string(ov::test::utils::DEVICE_NPU) + "." +
                          removeDeviceNameOnlyID(ov::test::utils::getTestsPlatformFromEnvironmentOr("3720"))),
        (ov::test::utils::appendPlatformTypeTestName<OVSpecificDeviceGetConfigTest>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVGetAvailableDevicesPropsTest, OVGetAvailableDevicesPropsTest,
                         ::testing::Values(ov::test::utils::DEVICE_NPU),
                         (ov::test::utils::appendPlatformTypeTestName<OVGetAvailableDevicesPropsTest>));

INSTANTIATE_TEST_SUITE_P(
        smoke_BehaviorTests_OVClassSpecificDeviceTest, OVSpecificDeviceTestSetConfig,
        ::testing::Values(std::string(ov::test::utils::DEVICE_NPU) + "." +
                          removeDeviceNameOnlyID(ov::test::utils::getTestsPlatformFromEnvironmentOr("3720"))),
        (ov::test::utils::appendPlatformTypeTestName<OVSpecificDeviceTestSetConfig>));

const std::vector<ov::AnyMap> multiConfigs = {{ov::device::priorities(ov::test::utils::DEVICE_NPU)}};

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVClassSetDevicePriorityConfigPropsTest,
                         OVClassSetDevicePriorityConfigPropsTest,
                         ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_HETERO),
                                            ::testing::ValuesIn(multiConfigs)),
                         (ov::test::utils::appendPlatformTypeTestName<OVClassSetDevicePriorityConfigPropsTest>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVGetMetricPropsTest, OVGetMetricPropsTest,
                         ::testing::Values(ov::test::utils::DEVICE_NPU),
                         (ov::test::utils::appendPlatformTypeTestName<OVGetMetricPropsTest>));

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests_OVGetMetricPropsOptionalTest, OVGetMetricPropsOptionalTest,
                         ::testing::Values(ov::test::utils::DEVICE_NPU),
                         (ov::test::utils::appendPlatformTypeTestName<OVGetMetricPropsOptionalTest>));

const std::vector<ov::AnyMap> configsDeviceProperties = {
        {ov::device::properties(ov::test::utils::DEVICE_NPU, ov::num_streams(ov::streams::AUTO))},
        {ov::device::properties(
                ov::AnyMap{{ov::test::utils::DEVICE_NPU, ov::AnyMap{ov::num_streams(ov::streams::AUTO)}}})}};

const std::vector<ov::AnyMap> configsDevicePropertiesDouble = {
        {ov::device::properties(ov::test::utils::DEVICE_NPU, ov::num_streams(-1)), ov::num_streams(ov::streams::AUTO)},
        {ov::device::properties(ov::test::utils::DEVICE_NPU, ov::num_streams(-1)),
         ov::device::properties(
                 ov::AnyMap{{ov::test::utils::DEVICE_NPU, ov::AnyMap{ov::num_streams(ov::streams::AUTO)}}}),
         ov::num_streams(-1)},
        {ov::device::properties(ov::test::utils::DEVICE_NPU, ov::num_streams(-1)),
         ov::device::properties(ov::test::utils::DEVICE_NPU, ov::num_streams(ov::streams::AUTO))},
        {ov::device::properties(ov::test::utils::DEVICE_NPU, ov::num_streams(ov::streams::AUTO)),
         ov::device::properties(ov::AnyMap{{ov::test::utils::DEVICE_NPU, ov::AnyMap{ov::num_streams(-1)}}})},
        {ov::device::properties(
                ov::AnyMap{{ov::test::utils::DEVICE_NPU, ov::AnyMap{ov::num_streams(ov::streams::AUTO)}}})}};

// IE Class load and check network with ov::device::properties
INSTANTIATE_TEST_SUITE_P(
        smoke_NPU_BehaviorTests_OVClassCompileModelAndCheckSecondaryPropertiesTest,
        OVClassCompileModelAndCheckSecondaryPropertiesTest,
        ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                           ::testing::ValuesIn(configsDeviceProperties)),
        (ov::test::utils::appendPlatformTypeTestName<OVClassCompileModelAndCheckSecondaryPropertiesTest>));

INSTANTIATE_TEST_SUITE_P(
        smoke_NPU_BehaviorTests_OVClassCompileModelAndCheckWithSecondaryPropertiesDoubleTest,
        OVClassCompileModelAndCheckSecondaryPropertiesTest,
        ::testing::Combine(::testing::Values(ov::test::utils::DEVICE_NPU),
                           ::testing::ValuesIn(configsDevicePropertiesDouble)),
        (ov::test::utils::appendPlatformTypeTestName<OVClassCompileModelAndCheckSecondaryPropertiesTest>));
};  // namespace
