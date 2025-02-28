
// Copyright (C) Intel Corporation
//
// SPDX-License-Identifier: Apache-2.0
//

#include "single_op_tests/embedding_segments_sum.hpp"
#include <vector>
#include "common_test_utils/test_constants.hpp"
#include "vpu_ov2_layer_test.hpp"

using namespace ov::test::utils;

namespace ov {
namespace test {

class EmbeddingSegmentsSumLayerTestCommon : public EmbeddingSegmentsSumLayerTest, virtual public VpuOv2LayerTest {};

class EmbeddingSegmentsSumLayerTest_NPU3720 : public EmbeddingSegmentsSumLayerTestCommon {};
class EmbeddingSegmentsSumLayerTest_NPU4000 : public EmbeddingSegmentsSumLayerTestCommon {};

TEST_P(EmbeddingSegmentsSumLayerTest_NPU3720, HW) {
    setDefaultHardwareMode();
    run(Platform::NPU3720);
}

TEST_P(EmbeddingSegmentsSumLayerTest_NPU4000, SW) {
    setReferenceSoftwareMode();
    run(Platform::NPU4000);
}

}  // namespace test
}  // namespace ov

using namespace ov::test;

namespace {

const std::vector<ov::element::Type> netPrecisions = {ov::element::i32, ov::element::f16, ov::element::f32,
                                                      ov::element::u8};

const std::vector<ov::element::Type> indPrecisions = {ov::element::i32};

const std::vector<std::vector<ov::Shape>> embTableShape = {{{5, 6, 4}}, {{10, 35, 8}}};
const std::vector<std::vector<size_t>> indices = {{0, 1, 2, 2, 3}};
const std::vector<std::vector<size_t>> segmentIds = {{0, 1, 2, 3, 4}};
const std::vector<size_t> numSegments = {7};
const std::vector<size_t> defaultIndex = {0};
const std::vector<bool> withWeights = {false, true};
const std::vector<bool> withDefaultIndex = {false, true};

const auto params = testing::Combine(::testing::ValuesIn(indices), ::testing::ValuesIn(segmentIds),
                                     ::testing::ValuesIn(numSegments), ::testing::ValuesIn(defaultIndex),
                                     ::testing::ValuesIn(withWeights), ::testing::ValuesIn(withDefaultIndex));

INSTANTIATE_TEST_CASE_P(smoke_EmbeddingSegmentsSumCheck1, EmbeddingSegmentsSumLayerTest_NPU3720,
                        ::testing::Combine(params,
                                           ::testing::ValuesIn(static_shapes_to_test_representation(embTableShape)),
                                           ::testing::ValuesIn(netPrecisions), ::testing::ValuesIn(indPrecisions),
                                           ::testing::Values(DEVICE_NPU)),
                        EmbeddingSegmentsSumLayerTest_NPU3720::getTestCaseName);

INSTANTIATE_TEST_CASE_P(smoke_EmbeddingSegmentsSumCheck1, EmbeddingSegmentsSumLayerTest_NPU4000,
                        ::testing::Combine(params,
                                           ::testing::ValuesIn(static_shapes_to_test_representation(embTableShape)),
                                           ::testing::ValuesIn(netPrecisions), ::testing::ValuesIn(indPrecisions),
                                           ::testing::Values(DEVICE_NPU)),
                        EmbeddingSegmentsSumLayerTest_NPU4000::getTestCaseName);

}  // namespace
