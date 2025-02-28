//
// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "behavior/ov_infer_request/batched_tensors.hpp"
#include <cctype>
#include "common/npu_test_env_cfg.hpp"
#include "common/utils.hpp"

using namespace ov::test::behavior;

namespace {

INSTANTIATE_TEST_SUITE_P(smoke_BehaviorTests, OVInferRequestBatchedTests,
                         ::testing::Values(ov::test::utils::DEVICE_NPU),
                         ov::test::utils::appendPlatformTypeTestName<OVInferRequestBatchedTests>);
}  // namespace
