//
// Copyright (C) 2022-2024 Intel Corporation
// SPDX-License-Identifier: Apache-2.0
//

#include "functional_test_utils/skip_tests_config.hpp"

#include <regex>
#include <string>
#include <vector>

#include "common/functions.h"
#include "common/npu_test_env_cfg.hpp"
#include "common/utils.hpp"
#include "common_test_utils/common_utils.hpp"
#include "functional_test_utils/ov_plugin_cache.hpp"
#include "npu_private_properties.hpp"

#include <intel_npu/utils/logger/logger.hpp>

class BackendName {
public:
    BackendName() {
        const auto corePtr = ov::test::utils::PluginCache::get().core();
        if (corePtr != nullptr) {
            _name = getBackendName(*corePtr);
        } else {
            _log.error("Failed to get OpenVINO Core from cache!");
        }
    }

    std::string getName() const {
        return _name;
    }

    bool isEmpty() const noexcept {
        return _name.empty();
    }

    bool isZero() const {
        return _name == "LEVEL0";
    }

    bool isVpual() const {
        return _name == "VPUAL";
    }

    bool isIMD() const {
        return _name == "IMD";
    }

private:
    std::string _name;
    intel_npu::Logger _log = intel_npu::Logger("BackendName", ov::log::Level::INFO);
};

class AvailableDevices {
public:
    AvailableDevices() {
        const auto corePtr = ov::test::utils::PluginCache::get().core();
        if (corePtr != nullptr) {
            _availableDevices = ::getAvailableDevices(*corePtr);
        } else {
            _log.error("Failed to get OpenVINO Core from cache!");
        }

        // Private device names may be registered via environment variables
        const std::string environmentDevice =
                ov::test::utils::getTestsPlatformFromEnvironmentOr(ov::intel_npu::Platform::AUTO_DETECT.data());
        const std::string standardizedEnvironmentDevice = ov::intel_npu::Platform::standardize(environmentDevice);

        if (std::all_of(_availableDevices.begin(), _availableDevices.end(), [&](const std::string& deviceName) {
                return deviceName.find(standardizedEnvironmentDevice) == std::string::npos;
            })) {
            _availableDevices.push_back(standardizedEnvironmentDevice);
        }
    }

    const auto& getAvailableDevices() const {
        return _availableDevices;
    }

    auto count() const {
        return _availableDevices.size();
    }

    bool has3720() const {
        return std::any_of(_availableDevices.begin(), _availableDevices.end(), [](const std::string& deviceName) {
            return deviceName.find("3720") != std::string::npos;
        });
    }

    bool has4000() const {
        return std::any_of(_availableDevices.begin(), _availableDevices.end(), [](const std::string& deviceName) {
            return deviceName.find("4000") != std::string::npos;
        });
    }

private:
    std::vector<std::string> _availableDevices;
    intel_npu::Logger _log = intel_npu::Logger("AvailableDevices", ov::log::Level::INFO);
};

class SkipRegistry {
public:
    void addPatterns(std::string&& comment, std::vector<std::string>&& patternsToSkip) {
        _registry.emplace_back(std::move(comment), std::move(patternsToSkip));
    }

    void addPatterns(bool conditionFlag, std::string&& comment, std::vector<std::string>&& patternsToSkip) {
        if (conditionFlag) {
            addPatterns(std::move(comment), std::move(patternsToSkip));
        }
    }

    /** Searches for the skip pattern to which passed test name matches.
     * Prints the message onto console if pattern is found and the test is to be skipped
     *
     * @param testName name of the current test being matched against skipping
     * @return Suitable skip pattern or empty string if none
     */
    std::string getMatchingPattern(const std::string& testName) const {
        for (const auto& entry : _registry) {
            for (const auto& pattern : entry._patterns) {
                std::regex re(pattern);
                if (std::regex_match(testName, re)) {
                    _log.info("%s; Pattern: %s", entry._comment.c_str(), pattern.c_str());
                    return pattern;
                }
            }
        }

        return std::string{};
    }

private:
    struct Entry {
        Entry(std::string&& comment, std::vector<std::string>&& patterns)
                : _comment{std::move(comment)}, _patterns{std::move(patterns)} {
        }

        std::string _comment;
        std::vector<std::string> _patterns;
    };

    std::vector<Entry> _registry;
    intel_npu::Logger _log = intel_npu::Logger("SkipRegistry", ov::log::Level::INFO);
};

std::string getCurrentTestName() {
    const auto* currentTestInfo = ::testing::UnitTest::GetInstance()->current_test_info();
    const auto currentTestName = currentTestInfo->test_case_name() + std::string(".") + currentTestInfo->name();
    return currentTestName;
}

std::vector<std::string> disabledTestPatterns() {
    // Initialize skip registry
    static const auto skipRegistry = []() {
        SkipRegistry _skipRegistry;

        const BackendName backendName;
        const AvailableDevices devices;

        // clang-format off

        //
        //  Disabled test patterns
        //
        // TODO
        _skipRegistry.addPatterns(
                "Tests break due to starting infer on IA side", {
                ".*CorrectConfigAPITests.*",
        });

        _skipRegistry.addPatterns(
                "ARM CPU Plugin is not available on Yocto", {
                ".*IEClassLoadNetworkTest.*HETERO.*",
                ".*IEClassLoadNetworkTest.*MULTI.*",
        });

        // TODO
        // [Track number: E#30810]
        _skipRegistry.addPatterns(
                "Hetero plugin doesn't throw an exception in case of big device ID", {
                ".*OVClassLoadNetworkTestNPU.*LoadNetworkHETEROWithBigDeviceIDThrows.*",
        });

        // TODO
        // [Track number: E#30815]
        _skipRegistry.addPatterns(
                "NPU Plugin doesn't handle DEVICE_ID in QueryNetwork implementation", {
                ".*OVClassQueryNetworkTest.*",
        });

        // [Track number: E#12774]
        _skipRegistry.addPatterns(
                "Cannot detect npu platform when it's not passed; Skip tests on Yocto which passes device without platform", {
                ".*IEClassLoadNetworkTest.LoadNetworkWithDeviceIDNoThrow.*",
                ".*IEClassLoadNetworkTest.LoadNetworkWithBigDeviceIDThrows.*",
                ".*IEClassLoadNetworkTest.LoadNetworkWithInvalidDeviceIDThrows.*",
        });

        // [Track number: E#28335]
        _skipRegistry.addPatterns(
                "Disabled test E#28335", {
                ".*smoke_LoadNetworkToDefaultDeviceNoThrow.*",
        });

        // [Track number: E#32241]
        _skipRegistry.addPatterns(
                "Disabled test E#28335", {
                ".*LoadNetwork.*CheckDeviceInBlob.*",
        });

        // [Track number: S#27343]
        _skipRegistry.addPatterns(
                "double free detected", {
                ".*InferConfigInTests\\.CanInferWithConfig.*",
        });

        // TODO:
        _skipRegistry.addPatterns(
                "GetExecGraphInfo function is not implemented for NPU plugin", {
                ".*checkGetExecGraphInfoIsNotNullptr.*",
                ".*CanCreateTwoExeNetworksAndCheckFunction.*",
                ".*CanCreateTwoCompiledModelsAndCheckRuntimeModel.*",
                ".*CheckExecGraphInfo.*",
                ".*canLoadCorrectNetworkToGetExecutable.*",
        });

        // [Track number: E#31074]
        _skipRegistry.addPatterns(
                "Disabled test E#28335", {
                ".*checkInferTime.*",
                ".*OVExecGraphImportExportTest.*",
        });

        _skipRegistry.addPatterns(
                "Test uses legacy OpenVINO 1.0 API, no need to support it", {
                ".*ExecutableNetworkBaseTest.checkGetMetric.*",
        });

        // TODO:
        _skipRegistry.addPatterns(
                "SetConfig function is not implemented for ExecutableNetwork interface (implemented only for npu plugin)", {
                ".*ExecutableNetworkBaseTest.canSetConfigToExecNet.*",
                ".*ExecutableNetworkBaseTest.canSetConfigToExecNetAndCheckConfigAndCheck.*",
                ".*CanSetConfigToExecNet.*",
        });

        // TODO
        // [Track number: E#30822]
        _skipRegistry.addPatterns(
                "Exception 'Not implemented'", {
                ".*OVClassNetworkTestP.*LoadNetworkCreateDefaultExecGraphResult.*",
        });

        _skipRegistry.addPatterns(
                "This is openvino specific test", {
                ".*ExecutableNetworkBaseTest.canExport.*",
        });

        _skipRegistry.addPatterns(
                "TensorIterator layer is not supported", {
                ".*ReturnResultNotReadyFromWaitInAsyncModeForTooSmallTimeout.*",
                ".*OVInferRequestDynamicTests.*",
                ".*OVInferenceChaining.*",
        });

        _skipRegistry.addPatterns(
                "Tests with unsupported precision", {
                ".*InferRequestCheckTensorPrecision.*type=boolean.*",
                ".*InferRequestCheckTensorPrecision.*type=bf16.*",
                ".*InferRequestCheckTensorPrecision.*type=f64.*",
                ".*InferRequestCheckTensorPrecision.*type=u1\\D.*",
        });

        _skipRegistry.addPatterns(!backendName.isZero() || !(devices.has3720() || devices.has4000()),
                "Tests enabled only for L0 NPU3720 and NPU4000", {
                // [Track number: E#70764]
                ".*InferRequestCheckTensorPrecision.*",
                ".*InferRequestIOTensorSetPrecisionTest.*",
                ".*DriverCompilerAdapterDowngradeInterpolate11TestNPU.*",
                ".*DriverCompilerAdapterInputsOutputsTestNPU.*",
        });

        // TODO
        // [Track number: E#32075]
        _skipRegistry.addPatterns(
                "Exception during loading to the device", {
                ".*OVClassLoadNetworkTestNPU.*LoadNetworkHETEROwithMULTINoThrow.*",
                ".*OVClassLoadNetworkTestNPU.*LoadNetworkMULTIwithHETERONoThrow.*",
        });

        _skipRegistry.addPatterns(
                "compiler: Unsupported arch kind: NPUX311X", {
                ".*CompilationForSpecificPlatform.*(3800|3900).*",
        });

        // [Track number: E#67741]
        _skipRegistry.addPatterns(
                "Cannot call setShape for Blobs", {
                R"(.*(smoke_Behavior|smoke_Multi_Behavior).*OVInferRequestIOTensorTest.*canInferAfterIOBlobReallocation.*)",
                R"(.*(smoke_Behavior|smoke_Multi_Behavior).*OVInferRequestIOTensorTest.*InferStaticNetworkSetChangedInputTensorThrow.*targetDevice=(NPU_|MULTI_configItem=MULTI_DEVICE_PRIORITIES_NPU).*)"
        });

        // [Track number: E#67749]
        _skipRegistry.addPatterns(
                "Can't loadNetwork without cache for ReadConcatSplitAssign with precision f32", {
                ".*CachingSupportCase_NPU.*CompileModelCacheTestBase.*CompareWithRefImpl.*ReadConcatSplitAssign.*",
        });

        // [Tracking number: E#99817]
        _skipRegistry.addPatterns(
                "NPU Plugin currently fails to get a valid output in these test cases", {
                ".*OVInferRequestIOTensorTest.InferStaticNetworkSetChangedInputTensorThrow.*",
                ".*OVInferRequestIOTensorTestNPU.InferStaticNetworkSetChangedInputTensorThrow.*",
                R"(.*OVInferRequestIOTensorTestNPU.InferStaticNetworkSetChangedInputTensorThrow/targetDevice=(NPU3720_|NPU4000_).*)",
                R"(.*OVInferRequestIOTensorTestNPU.InferStaticNetworkSetChangedInputTensorThrow/targetDevice=(NPU3720_|NPU4000_)configItem=MULTI_DEVICE_PRIORITIES_NPU_.*)",
                R"(.*OVInferRequestIOTensorTest.InferStaticNetworkSetChangedInputTensorThrow/targetDevice=(NPU3720_|NPU4000_).*)",
                R"(.*OVInferRequestIOTensorTest.InferStaticNetworkSetChangedInputTensorThrow/targetDevice=(NPU3720_|NPU4000_)configItem=MULTI_DEVICE_PRIORITIES_NPU_.*)",
        });

        // [Track number: E#68774]
        _skipRegistry.addPatterns(
                "OV requires the plugin to throw when value of DEVICE_ID is unrecognized, but plugin does not throw", {
                "smoke_BehaviorTests.*IncorrectConfigTests.SetConfigWithIncorrectKey.*(SOME_DEVICE_ID|DEVICE_UNKNOWN).*",
                "smoke_BehaviorTests.*IncorrectConfigTests.SetConfigWithNoExistingKey.*SOME_DEVICE_ID.*",
                "smoke_BehaviorTests.*IncorrectConfigAPITests.SetConfigWithNoExistingKey.*(SOME_DEVICE_ID|DEVICE_UNKNOWN).*",
        });

        // [Track number: E#77755]
        _skipRegistry.addPatterns(
                "OV requires the plugin to throw on network load when config file is incorrect, but plugin does not throw", {
                R"(.*smoke_Auto_BehaviorTests.*IncorrectConfigTests.CanNotLoadNetworkWithIncorrectConfig.*AUTO_config.*unknown_file_MULTI_DEVICE_PRIORITIES=(NPU_|NPU,CPU_).*)"
        });

        // [Track number: E#77756]
        _skipRegistry.addPatterns(
                "OV expects the plugin to not throw any exception on network load, but it actually throws", {
                R"(.*(smoke_Multi_Behavior|smoke_Auto_Behavior).*SetPropLoadNetWorkGetPropTests.*SetPropLoadNetWorkGetProperty.*)"
        });

        // [Track number: E#68776]
        _skipRegistry.addPatterns(
                "Plugin can not perform SetConfig for value like: device=NPU config key=LOG_LEVEL value=0", {
                "smoke_BehaviorTests/DefaultValuesConfigTests.CanSetDefaultValueBackToPlugin.*",
        });

        _skipRegistry.addPatterns(
                "Disabled with ticket number", {
                // [Track number: E#48480]
                ".*OVExecutableNetworkBaseTest.*",

                // [Track number: E#63708]
                ".*smoke_BehaviorTests.*InferStaticNetworkSetInputTensor.*",
                ".*smoke_Multi_BehaviorTests.*InferStaticNetworkSetInputTensor.*",

                // [Track number: E#64490]
                 ".*OVClassNetworkTestP.*SetAffinityWithConstantBranches.*"
        });

        // [Tracking number: E#86380]
        _skipRegistry.addPatterns(
                "The output tensor gets freed when the inference request structure's destructor is called. The issue is unrelated to the caching feature.", {
                ".*CacheTestBase.CompareWithRefImpl.*",
        });

        _skipRegistry.addPatterns(
                "Expected: ie->SetConfig(configuration, target_device) throws an exception of type InferenceEngine::Exception. Throws nothing.", {
                // [Tracking number: E#89274]
                ".*AutoBatch.*Behavior.*IncorrectConfigAPITests.SetConfigWithNoExistingKey.*AUTO_BATCH_TIMEOUT.*",
                // [Track number: E#89084]
                ".*AutoBatch.*Behavior.*IncorrectConfigTests.SetConfigWithIncorrectKey.*AUTO_BATCH_TIMEOUT.*",
                ".*AutoBatch.*Behavior.*IncorrectConfigTests.CanNotLoadNetworkWithIncorrectConfig.*AUTO_BATCH_TIMEOUT.*",
        });

        _skipRegistry.addPatterns(
                "Dynamic I/O shapes are being used when running the tests. This feature is not yet supported by the NPU plugin.", {
                ".*SetPreProcessTo.*"
        });

        _skipRegistry.addPatterns(
                "This scenario became invalid upon refactoring the implementation as to use the 2.0 OV API. "
                "The legacy version structure contains major and minor version attributes, but these fields are not found anymore "
                "in the corresponding 2.0 API structure.", {
                ".*smoke_BehaviorTests/VersionTest.pluginCurrentVersionIsCorrect.*"
        });

        // [Tracking number: E#102428]
        _skipRegistry.addPatterns(
                "Tests throw errors as expected but drivers post-v.1657 will fail to catch them", {
                ".*FailGracefullyTest.*",
                ".*QueryNetworkTestSuite3NPU.*"
        });

        //
        // Conditionally disabled test patterns
        //

        _skipRegistry.addPatterns(devices.count() && !devices.has3720(), "Tests are disabled for all devices except NPU3720",
                                  {
                                          ".*NPU3720.*",
                                          // [Track number: E#84621]
                                          ".*DriverCompilerAdapterDowngradeInterpolate11TestNPU.*",
                                          ".*DriverCompilerAdapterInputsOutputsTestNPU.*",
                                  });

        _skipRegistry.addPatterns(
                backendName.isEmpty(), "Disabled for when backend is empty (i.e., no device)",
                {
                        // Cannot run InferRequest tests without a device to infer to
                        ".*InferRequest.*",
                        ".*OVInferRequest.*",
                        ".*OVInferenceChaining.*",
                        ".*ExecutableNetworkBaseTest.*",
                        ".*OVExecutableNetworkBaseTest.*",
                        ".*ExecNetSetPrecision.*",
                        ".*SetBlobTest.*",
                        ".*InferRequestCallbackTests.*",
                        ".*PreprocessingPrecisionConvertTest.*",
                        ".*SetPreProcessToInputInfo.*",
                        ".*InferRequestPreprocess.*",
                        ".*HoldersTestOnImportedNetwork.*",
                        ".*HoldersTest.Orders.*",
                        ".*HoldersTestImportNetwork.Orders.*",

                        // Cannot compile network without explicit specifying of the platform in case of no devices
                        ".*OVExecGraphImportExportTest.*",
                        ".*OVHoldersTest.*",
                        ".*OVClassExecutableNetworkGetMetricTest.*",
                        ".*OVClassExecutableNetworkGetConfigTest.*",
                        ".*OVClassNetworkTestP.*SetAffinityWithConstantBranches.*",
                        ".*OVClassNetworkTestP.*SetAffinityWithKSO.*",
                        ".*OVClassNetworkTestP.*LoadNetwork.*",
                        ".*FailGracefullyTest.*",
                        ".*DriverCompilerAdapterInputsOutputsTestNPU.*",

                        // Exception in case of network compilation without devices in system
                        // [Track number: E#30824]
                        ".*OVClassImportExportTestP.*",
                        ".*OVClassLoadNetworkTestNPU.*LoadNetwork.*",
                        // [Track number: E#84621]
                        ".*DriverCompilerAdapterDowngradeInterpolate11TestNPU.*",
                        ".*QueryNetworkTestSuite.*",
                });

        // [Tracking number: E#111510]
        _skipRegistry.addPatterns("Failing test for NPU device", {
                ".*OVClassImportExportTestP.*OVClassCompiledModelImportExportTestP.*ImportNetworkThrowWithDeviceName.*"
        });

        _skipRegistry.addPatterns(!(backendName.isZero()), "These tests runs only on LevelZero backend",
                                  {".*InferRequestRunTests.*",
                                   ".*OVClassGetMetricAndPrintNoThrow.*",
                                   ".*IEClassGetMetricAndPrintNoThrow.*",
                                   ".*CompileModelLoadFromFileTestBase.*",
                                   ".*CorrectConfigTests.*"});

        _skipRegistry.addPatterns(!(devices.has3720()), "Runs only on NPU3720 with Level Zero enabled #85493",
                                  {".*InferRequestRunTests.MultipleExecutorStreamsTestsSyncInfers.*"});

        _skipRegistry.addPatterns("Other devices than NPU doesn't allow to set NPU properties with OV1.0 and CACHE_DIR + MLIR is not supported",
                                  {".*smoke_AutoBatch_BehaviorTests/CorrectConfigTests.*"});

        _skipRegistry.addPatterns("OpenVINO issues when using caching mechanism",
                                  {// [Tracking number: C#119359]
                                   ".*smoke_Auto_BehaviorTests_CachingSupportCase_NPU_Driver/CompileModelLoadFromFileTestBase.*",
                                   // [Tracking number: C#120240]
                                   ".*smoke_BehaviorTests_CachingSupportCase_NPU_Driver/CompileModelLoadFromFileTestBase.*"});

        // [Tracking number: E#119397]
        _skipRegistry.addPatterns(backendName.isZero() && devices.has4000(),
                "Test fails compilation (on both Ubuntu and Windows)", {
                ".*DetectionOutputLayerTestCommon.NPU4000.*"
        });

#ifdef WIN32
#elif defined(__linux__)
        // [Tracking number: E#103391]
        _skipRegistry.addPatterns(backendName.isZero() && (devices.has3720() || devices.has4000()),
                "IfTest segfaults npuFuncTest on Ubuntu", {
                ".*smoke_IfTest.*"
        });
#endif

        // [Tracking number: E#107154]
        _skipRegistry.addPatterns(
                "Can't disable ELF Backend since Graphfile does not work on linux", {
                ".*NPU_USE_ELF_COMPILER_BACKEND:NO.*",
                ".*USE_ELF_COMPILER_BACKEND_NO.*"
        });

        _skipRegistry.addPatterns(backendName.isIMD(), "IMD/Simics do not support the tests",
                                  {
                                        // [Tracking number: E#81065]
                                        ".*smoke_ClassPluginProperties.*DEVICE_UUID.*",
                                  });
        _skipRegistry.addPatterns(backendName.isIMD(), "Run long time on IMD/Simics",
                                  {
                                        // [Tracking number: E#85488]
                                        ".*PreprocessingPrecisionConvertTestNPU.*",
                                  });

        // [Track number: E#83423]
        _skipRegistry.addPatterns(!backendName.isZero() || !devices.has3720(),
                "Tests enabled only for L0 NPU3720", {
                ".*smoke_VariableStateBasic.*"
        });

        // [Track number: E#83708]
        _skipRegistry.addPatterns(backendName.isZero(),
                "MemoryLSTMCellTest failing with NOT_IMPLEMENTED", {
                ".*smoke_MemoryLSTMCellTest.*"
        });

        // [Track number: E#118999]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Newly enabled, never tested", {
                ".*smoke_BehaviorTests_Driver/OVCompiledGraphImportExportTest.importExportedFunctionConstantResultOnly.*",
                ".*smoke_BehaviorTests_OVClassImportExportTestP/OVClassCompiledModelImportExportTestP.smoke_ImportNetworkThrowWithDeviceName.*",
                ".*ClassExecutableNetworkTestSuite1NPU.PropertyIsSupportedAndImmutableAndGet.*",
                ".*ClassExecutableNetworkTestSuite2NPU.PropertyIsSupportedAndImmutableAndCanNotSet.*",
                ".*smoke_BehaviorTests_ClassPluginPropertiesTest/ClassPluginPropertiesTestSuite2NPU.CanNotSetImmutableProperty.*",
                ".*smoke_BehaviorTests_ClassPluginPropertiesOptsTest1NPU/ClassPluginPropertiesTestSuite3NPU.CanGetPropertyWithOptionsNotAffectingCore.*",
                ".*ClassPluginPropertiesTestSuite4NPU.CanNotSetGetInexistentProperty.*",
                ".*BehaviorTests_OVCheckSetSupportedRWMandatoryMetricsPropsTests/OVCheckSetSupportedRWMetricsPropsTests.ChangeCorrectProperties.*"
        });

        _skipRegistry.addPatterns(!backendName.isZero() || !devices.has3720(),
                "QueryNetwork is only supported by 3720 platform", {
                ".*QueryNetworkTestSuite.*"
        });

        _skipRegistry.addPatterns(
                devices.count() > 1,
                "Some NPU Plugin metrics require single device to work in auto mode or set particular device",
                {
                        ".*OVClassGetConfigTest.*GetConfigNoThrow.*",
                        ".*OVClassGetConfigTest.*GetConfigHeteroNoThrow.*",
                });

        // [Tracking number: E#111455]
        _skipRegistry.addPatterns("Failing properties tests for AUTO / MULTI", {
                ".*OVCheckSetSupportedRWMetricsPropsTests.ChangeCorrectProperties.*MULTI.*LOG_LEVEL.*",
                ".*OVCheckSetSupportedRWMetricsPropsTests.ChangeCorrectProperties.*AUTO.*LOG_LEVEL.*"
        });

        // [Tracking number: E#99817]
        _skipRegistry.addPatterns(backendName.isZero() && (devices.has3720() || devices.has4000()),
                "Disabled tests for NPU3720 and NPU4000", {
                ".*InferRequestVariableStateTest.inferreq_smoke_VariableState_2infers.*",
                ".*OVInferRequestIOTensorTest.*InferStaticNetworkSetChangedInputTensorThrow.*"
        });

        // TODO
        _skipRegistry.addPatterns(
                "GetExecGraphInfo function is not implemented for NPU plugin", {
                ".*CanCreateTwoCompiledModelsAndCheckRuntimeModel.*",
        });

        // TODO
        _skipRegistry.addPatterns("Fails with CID", {
                ".*smoke_BehaviorTests_OVClassLoadNetworkTest_Driver/OVClassLoadNetworkTestNPU.LoadNetworkHETEROWithDeviceIDNoThrow.*NPU_COMPILER_TYPE_DRIVER.*"
        });

#ifdef WIN32
        // [Track number: C#128116]
        _skipRegistry.addPatterns("Unicode paths for ov::cache_dir are not correctly handled on Windows",
                                  {".*CompiledKernelsCacheTest.*CanCreateCacheDirAndDumpBinariesUnicodePath.*"});
#endif

        // [Tracking number: E#108600]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Unsupported NPU properties", {
                ".*OVCheckSetSupportedRWMetricsPropsTests.ChangeCorrectProperties.*EXECUTION_MODE_HINT.*",
                ".*OVCheckChangePropComplieModleGetPropTests_InferencePrecision.*",
                ".*OVCheckMetricsPropsTests_ModelDependceProps.*",
                ".*OVCheckChangePropComplieModleGetPropTests_DEVICE_ID.*ENABLE_CPU_PINNING.*",
                ".*OVClassCompileModelAndCheckSecondaryPropertiesTest.*"
        });

        // [Tracking number: E#108600]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Failing properties tests", {
                ".*OVSpecificDeviceSetConfigTest.GetConfigSpecificDeviceNoThrow.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*DEVICE_ID.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*NPU_COMPILATION_MODE.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*NPU_COMPILATION_MODE_PARAMS.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*NPU_PROFILING_OUTPUT_FILE.*"
        });

        // [Tracking number: E#109040]
        _skipRegistry.addPatterns("Disabled all tests CompileForDifferentPlatformsTests with config NPU_COMPILER_TYPE_DRIVER", {
                ".*smoke_BehaviorTest_Driver/CompileForDifferentPlatformsTests.*NPU_COMPILER_TYPE_DRIVER.*"
        });

        // TODO
        _skipRegistry.addPatterns(
                "GetExecGraphInfo function is not implemented for NPU plugin", {
                ".*CanCreateTwoCompiledModelsAndCheckRuntimeModel.*",
        });

        // TODO
        _skipRegistry.addPatterns("Fails with CID", {
                ".*smoke_BehaviorTests_OVClassLoadNetworkTest_Driver/OVClassLoadNetworkTestNPU.LoadNetworkHETEROWithDeviceIDNoThrow.*NPU_COMPILER_TYPE_DRIVER.*"
        });

        // [Tracking number: E#114622]
        _skipRegistry.addPatterns(!devices.has3720(),
                "The implementation does not allow passing extra configuration options. This prohibits specifying the private platform codes explicitly.", {
                ".*smoke_OVClassImportExportTestP/OVClassCompiledModelImportExportTestP.smoke_ImportNetworkNoThrowWithDeviceName.*",
                ".*nightly_OVClassModelOptionalTestP/OVClassModelOptionalTestP.CompileModel.*",
                ".*smoke_BehaviorTests_OVCheckSetSupportedRWMetricsPropsTests/.*",
                ".*OVHoldersTest.*",
                ".*OVHoldersTestOnImportedNetwork.*",
                ".*OVHoldersTestWithConfig.*",
                ".*OVInferRequestBatchedTests.*",
                ".*OVInferRequestInferenceTests.*"
        });

        // [Tracking number: E#114623]
        _skipRegistry.addPatterns(!devices.has3720(),
                "The private platform names cannot be identified via the \"ov::available_devices\" configuration.", {
                ".*smoke_BehaviorTests_OVClassSetDefaultDeviceIDPropTest/OVClassSetDefaultDeviceIDPropTest.SetDefaultDeviceIDNoThrow.*",
                ".*smoke_BehaviorTests_OVClassSpecificDeviceTest/OVSpecificDeviceGetConfigTest.GetConfigSpecificDeviceNoThrow.*",
                ".*smoke_BehaviorTests_OVClassSpecificDeviceTest/OVSpecificDeviceTestSetConfig.SetConfigSpecificDeviceNoThrow.*"
        });

        // [Tracking number: E#114624]
        _skipRegistry.addPatterns(
                "The tests are not actually running the compiler-in-driver module.", {
                ".*smoke_BehaviorTests_OVCheckSetSupportedRWMetricsPropsTests_Driver/.*"
        });

        // [Tracking number: E#109040]
        _skipRegistry.addPatterns(devices.has3720() || devices.has4000(),
                "Disabled tests for NPU3720 and NPU3720 and NPU4000", {
                ".*smoke.*_BehaviorTests_Driver/OVInferRequestCheckTensorPrecision.*type=i16.*DRIVER.*",
                ".*smoke.*_BehaviorTests_Driver/OVInferRequestCheckTensorPrecision.*type=u16.*DRIVER.*",
                ".*smoke.*_BehaviorTests_Driver/OVInferRequestCheckTensorPrecision.*type=u64.*DRIVER.*",
                ".*smoke_OVClassLoadNetworkTest_Driver/OVClassLoadNetworkTestNPU.*DRIVER.*",
        });

        // [Tracking number: E#112064]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Failing core threading tests", {
                ".*CoreThreadingTest.smoke_QueryModel.*",
                ".*CoreThreadingTestsWithIter.smoke_CompileModel.*",
                ".*CoreThreadingTestsWithIter.smoke_CompileModel_Accuracy_SingleCore.*",
                ".*CoreThreadingTestsWithIter.smoke_CompileModel_Accuracy_MultipleCores.*",
                ".*CoreThreadingTestsWithIter.nightly_AsyncInfer_ShareInput.*"
        });

        // [Tracking number: E#108600]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Failing properties tests", {
                ".*OVSpecificDeviceSetConfigTest.GetConfigSpecificDeviceNoThrow.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*DEVICE_ID.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*NPU_COMPILATION_MODE.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*NPU_COMPILATION_MODE_PARAMS.*",
                ".*OVPropertiesIncorrectTests.SetPropertiesWithIncorrectKey.*NPU_PROFILING_OUTPUT_FILE.*"
        });

        // [Tracking number: E#117582]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Failing core threading test with cache enabled", {
                ".*CoreThreadingTest.*CoreThreadingTestsWithCacheEnabled.*"
        });

        // [Tracking number: E#118331]
        _skipRegistry.addPatterns(backendName.isZero() && !devices.has3720(),
                "platform and compiler_type are private", {
                ".*smoke_Multi_BehaviorTests/OVInferRequestCallbackTests.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestCallbackTests.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestCallbackTestsNPU.*",
                ".*smoke_Multi_BehaviorTests_OVClassCompileModelWithCorrectPropertiesTest/OVClassCompileModelWithCorrectPropertiesTest.*",
                ".*smoke_AUTO_BehaviorTests_OVClassCompileModelWithCorrectPropertiesTest/OVClassCompileModelWithCorrectPropertiesTest.*",
                // [Tracking number: C#140844]
                ".*smoke_Auto_BehaviorTests/OVInferRequestIOTensorTest.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestCallbackTestsNPU.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestIOTensorTestNPU.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestIOTensorTest.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestMultithreadingTests.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestMultithreadingTestsNPU.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestPerfCountersExceptionTest.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestPerfCountersTest.*",
                ".*smoke_Multi_BehaviorTests/OVInferRequestWaitTests.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestMultithreadingTests.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestMultithreadingTestsNPU.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestPerfCountersExceptionTest.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestPerfCountersTest.*",
                ".*smoke_Auto_BehaviorTests/OVInferRequestWaitTests.*",
                ".*smoke_OVClassNetworkTestP/OVClassNetworkTestPNPU.*",
                ".*smoke_OVClassLoadNetworkTest/OVClassLoadNetworkTestNPU.*",
                ".*smoke_Hetero_BehaviorTests_VariableState/OVInferRequestVariableStateTest.*"
        });

        // [Tracking number: E#118331]
        _skipRegistry.addPatterns(backendName.isZero(),
                "Private properties cannot be accessed by HETERO compiled model", {
                        ".*smoke_Hetero_BehaviorTests.*OVClassCompiledModelGetPropertyTest_MODEL_PRIORITY.*",
                        ".*smoke_Hetero_BehaviorTests.*OVClassCompiledModelGetPropertyTest_EXEC_DEVICES.*",
                        ".*smoke_Hetero_BehaviorTests.*OVCompileModelGetExecutionDeviceTests.*"
        });

        // [Tracking number: E#118331]
        _skipRegistry.addPatterns(backendName.isZero() && !devices.has3720(),
                "platform and compiler_type are private", {
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestCallbackTests.*",
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestCallbackTests.*",
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestCallbackTestsNPU.*",
                ".*smoke_Multi_BehaviorTests_OVClassCompileModelWithCorrectPropertiesTest_Driver/OVClassCompileModelWithCorrectPropertiesTest.*",
                ".*smoke_AUTO_BehaviorTests_OVClassCompileModelWithCorrectPropertiesTest_Driver/OVClassCompileModelWithCorrectPropertiesTest.*",
                // [Tracking number: C#140844]
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestIOTensorTest.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestCallbackTestsNPU.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestIOTensorTestNPU.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestIOTensorTest.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestMultithreadingTests.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestPerfCountersTest.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestPerfCountersExceptionTest.*",
                ".*smoke_Multi_BehaviorTests_Driver/OVInferRequestWaitTests.*",
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestMultithreadingTestsNPU.*",
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestPerfCountersTest.*",
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestPerfCountersExceptionTest.*",
                ".*smoke_Auto_BehaviorTests_Driver/OVInferRequestWaitTests.*",
                ".*smoke_OVClassNetworkTestP_Driver/OVClassNetworkTestPNPU.*"
        });

        // [Tracking number: E#116494]
        _skipRegistry.addPatterns(
                "NPU plugin doesn't implement `set_tensors` function", {
                ".*OVInferRequestBatchedTests.SetInputTensorsBase.*",
                ".*OVInferRequestBatchedTests.SetInputTensorsAsync.*",
                ".*OVInferRequestBatchedTests.SetInputTensors_override_with_set.*",
                ".*OVInferRequestBatchedTests.SetInputTensorsBase_Caching.*",
                ".*OVInferRequestBatchedTests.SetInputTensors_Multiple_Infer.*",
                ".*OVInferRequestBatchedTests.SetInputTensors_Can_Infer_Dynamic.*",
                ".*OVInferRequestBatchedTests.SetInputTensors_Get_Tensor_Not_Allowed.*",
                ".*OVInferRequestBatchedTests.SetInputTensors_Correct_all.*",
                ".*OVInferRequestBatchedTests.SetInputTensors_Cache_CheckDeepCopy.*"
        });

        // [Tracking number: E#118381]
        _skipRegistry.addPatterns("Comparation is failed, SLT need to be updated.", {
                ".*smoke.*GridSample_Tiling/GridSampleLayerTest.*align_corners=0.*Mode=nearest_padding_mode=zeros.*",
                ".*smoke.*GridSample_Tiling/GridSampleLayerTest.*align_corners=0.*Mode=nearest_padding_mode=border.*",
                ".*smoke.*GridSample_Tiling/GridSampleLayerTest.*align_corners=0.*Mode=nearest_padding_mode=reflection.*"
        });

        // [Tracking number: E#124588]
        _skipRegistry.addPatterns(devices.has3720(),
                "Sporadic fail on RoiAlign test will block PR checker", {
                ".*precommit_ROIAlign/ROIAlignV9LayerTest_NPU3720.*(2.4.20.40).*",
        });


        // [Tracking number: E#116575]
        _skipRegistry.addPatterns(
                "NPU fails for `OVIterationChaining.Simple` tests", {
                ".*OVIterationChaining.Simple.*"
        });

        // [Tracking number: E#116596]
        _skipRegistry.addPatterns(
                "Missing model ops in profiling info", {
                ".*OVInferRequestPerfCountersTest.CheckOperationInProfilingInfo.*"
        });

        // [Tracking number: E#118045]
        _skipRegistry.addPatterns(
                "NPU needs to implement ROITensor logic in zero_infer_request", {
                ".*OVInferRequestInferenceTests.Inference_ROI_Tensor/roi_nchw.*"
        });

        // [Tracking number: E#116761]
        _skipRegistry.addPatterns("OVClassQueryModel tests do not work with COMPILER_TYPE=DRIVER", {
                ".*OVClassQueryModelTest.QueryModelHETEROWithDeviceIDNoThrow.*",
                ".*OVClassQueryModelTest.QueryModelWithBigDeviceIDThrows.*",
                ".*OVClassQueryModelTest.QueryModelWithInvalidDeviceIDThrows.*"
        });

        // [Tracking number: E#116762]
        _skipRegistry.addPatterns("softMaxDynamicTest4D_NPU3720 tests do not work with COMPILER_TYPE=DRIVER", {
                ".*SoftMaxLayerTestNPU.CompareWithRef.*"
        });

        // [Tracking number: E#109040]
	_skipRegistry.addPatterns("CheckWrongGraphExtAndThrow tests do not work with COMPILER_TYPE=DRIVER", {
                ".*DriverCompilerAdapterExpectedThrowNPU.CheckWrongGraphExtAndThrow.*"
        });

        // [Tracking number: E#109040]
	_skipRegistry.addPatterns("Skip tests that can not wrong when DRIVER is default compiler type", {
                ".*OVClassLoadNetworkTestNPU.LoadNetworkHETEROWithDeviceIDNoThrow.*",
                ".*MatMulTransposeConcatTest.*"
        });

        // [Tracking number: E#121043]
        _skipRegistry.addPatterns("Compiler adapter is not extracting network name from metadata", {
                ".*smoke_BehaviorTests/OVClassCompiledModelGetPropertyTest.GetMetricNoThrow_NETWORK_NAME.*"
        });

        // [Tracking number: E#121347]
        _skipRegistry.addPatterns("Error message for empty model from stream must be changed to have \"device xml header\"", {
                ".*smoke_BehaviorTests/OVClassCompiledModelImportExportTestP.smoke_ImportNetworkThrowWithDeviceName.*",
                ".*smoke_Hetero_BehaviorTests/OVClassCompiledModelImportExportTestP.smoke_ImportNetworkThrowWithDeviceName.*"
        });

        _skipRegistry.addPatterns("NPU cannot set properties for compiled models", {
                ".*OVClassCompiledModelSetCorrectConfigTest.canSetConfig.*"
        });

        // [Tracking number: C#139118]
        _skipRegistry.addPatterns("Failing runtime model tests", {
                ".*OVCompiledModelGraphUniqueNodeNamesTest.CheckUniqueNodeNames.*",
                ".*OVExecGraphSerializationTest.ExecutionGraph.*"
        });

        return _skipRegistry;
    }();
    // clang-format on

    std::vector<std::string> matchingPatterns;
    const auto currentTestName = getCurrentTestName();
    matchingPatterns.emplace_back(skipRegistry.getMatchingPattern(currentTestName));

    return matchingPatterns;
}
