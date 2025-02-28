//
// Copyright (C) 2022-2023 Intel Corporation
// SPDX-License-Identifier: Apache-2.0
//

#include "single_op_tests/extract_image_patches.hpp"
#include <vector>
#include "common_test_utils/test_constants.hpp"
#include "vpu_ov2_layer_test.hpp"

using namespace ov::test::utils;

namespace ov {
namespace test {

class ExtractImagePatchesLayerTestCommon : public ExtractImagePatchesTest, virtual public VpuOv2LayerTest {};

class ExtractImagePatchesLayerTest_NPU3720 : public ExtractImagePatchesLayerTestCommon {};
class ExtractImagePatchesLayerTest_NPU4000 : public ExtractImagePatchesLayerTestCommon {};

TEST_P(ExtractImagePatchesLayerTest_NPU3720, SW) {
    setReferenceSoftwareMode();
    run(Platform::NPU3720);
}

TEST_P(ExtractImagePatchesLayerTest_NPU4000, SW) {
    setReferenceSoftwareMode();
    run(Platform::NPU4000);
}
}  // namespace test
}  // namespace ov

using ov::op::PadType;
using namespace ov::test;

namespace {

const std::vector<PadType> paddingType = {PadType::VALID, PadType::SAME_UPPER, PadType::SAME_LOWER};
const std::vector<std::vector<size_t>> strides = {{5, 5}};
const std::vector<std::vector<size_t>> rates = {{2, 2}};

// FP16
const auto test1ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 1, 10, 10}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{3, 3}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{5, 5}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}, {2, 2}}),                   // rates
        ::testing::ValuesIn({PadType::VALID}),                                                   // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke1_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test1ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke1_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test1ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test2ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 1, 10, 10}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{4, 4}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{8, 8}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}}),                           // rates
        ::testing::ValuesIn({PadType::VALID}),                                                   // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke2_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test2ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke2_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test2ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test3ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 1, 10, 10}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{4, 4}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{9, 9}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}, {2, 2}}),                   // rates
        ::testing::ValuesIn({PadType::SAME_UPPER}),                                              // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke3_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test3ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke3_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test3ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test4ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 2, 5, 5}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                         // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{3, 3}}),                         // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}}),                         // rates
        ::testing::ValuesIn({PadType::VALID}),                                                 // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke4_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test4ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke4_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test4ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test5ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 64, 26, 26}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                            // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                            // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                            // rates
        ::testing::ValuesIn({PadType::SAME_LOWER}),                                               // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke5_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test5ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke5_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test5ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test6ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{2, 1, 10, 10}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{3, 3}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{5, 5}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}}),                           // rates
        ::testing::ValuesIn({PadType::SAME_UPPER, PadType::SAME_LOWER}),                         // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke6_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test6ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke6_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test6ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test7ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{2, 3, 13, 37}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 3}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 4}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}}),                           // rates
        ::testing::ValuesIn({PadType::VALID, PadType::SAME_LOWER}),                              // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke7_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test7ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke7_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test7ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto test8ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{2, 3, 13, 37}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 3}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 4}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}}),                           // rates
        ::testing::ValuesIn({PadType::SAME_UPPER}),                                              // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke8_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test8ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke8_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test8ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

// I32
const auto test9ExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 64, 26, 26}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                            // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                            // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{1, 1}}),                            // rates
        ::testing::ValuesIn(paddingType),                                                         // pad type
        ::testing::ValuesIn({ov::element::i32}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke9_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        test9ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke9_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        test9ExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

const auto testPrecommitExtractImagePatchesParams = ::testing::Combine(
        ::testing::ValuesIn({static_shapes_to_test_representation({ov::Shape{1, 3, 10, 10}})}),  // input shape
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{3, 3}}),                           // kernel size
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{5, 5}}),                           // strides
        ::testing::ValuesIn(std::vector<std::vector<size_t>>{{2, 2}}),                           // rates
        ::testing::ValuesIn({PadType::VALID}),                                                   // pad type
        ::testing::ValuesIn({ov::element::f16}), ::testing::Values(DEVICE_NPU));

INSTANTIATE_TEST_CASE_P(smoke_precommit_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU3720,
                        testPrecommitExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke_precommit_ExtractImagePatches, ExtractImagePatchesLayerTest_NPU4000,
                        testPrecommitExtractImagePatchesParams, ExtractImagePatchesTest::getTestCaseName);

}  // namespace
