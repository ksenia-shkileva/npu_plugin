//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#pragma once

#include "vpux/compiler/core/attributes/shape.hpp"
#include "vpux/compiler/core/type_interfaces.hpp"
#include "vpux/utils/core/numeric.hpp"

#include "vpux/compiler/dialect/IE/IR/attributes.hpp"
#include "vpux/compiler/dialect/VPURT/IR/attributes.hpp"

#include <mlir/Dialect/Quant/QuantTypes.h>
#include <mlir/IR/BuiltinTypes.h>

#include <llvm/ADT/bit.h>

#include <flatbuffers/flatbuffers.h>

#include <cstdint>
#include <tuple>

namespace vpux {

static constexpr int64_t MAX_LEVELS = 256;

//
// Utilities for quantized types
//

mlir::LogicalResult validateQuantElemType(mlir::Location loc, vpux::NDTypeInterface mainType);

mlir::Type normalizeQuantStorageType(mlir::quant::QuantizedType qType);

mlir::quant::UniformQuantizedPerAxisType expandScalesAndZP(mlir::quant::UniformQuantizedPerAxisType perAxisQType,
                                                           ShapeRef padBefore, ShapeRef padAfter);

mlir::quant::UniformQuantizedPerAxisType tileScalesAndZP(mlir::quant::UniformQuantizedPerAxisType perAxisQType,
                                                         ShapeRef shape, ShapeRef offsets);

mlir::quant::UniformQuantizedPerAxisType changeAxis(mlir::quant::UniformQuantizedPerAxisType perAxisQType,
                                                    int32_t axis);

mlir::quant::QuantizedType changeStorageType(mlir::quant::QuantizedType qType, mlir::Type storageType);

bool canBeMerged(mlir::quant::UniformQuantizedPerAxisType type1, mlir::quant::UniformQuantizedPerAxisType type2);
mlir::quant::UniformQuantizedPerAxisType concatScalesAndZP(ArrayRef<mlir::quant::UniformQuantizedPerAxisType> types);

using Scales = SmallVector<double>;
using ZeroPoints = SmallVector<int64_t>;

std::pair<Scales, ZeroPoints> extractScalesAndZeroPoints(mlir::Type tensorElemType);
Scales exractWeightsScales(mlir::Type weightsElemType);

template <typename MultType>
std::tuple<MultType, uint8_t, int8_t> approximate(uint8_t bits, double target) {
    int exponent = 0;
    const auto mantissa = std::frexp(target, &exponent);

    const auto mult = checked_cast<MultType>(mantissa * std::pow(2, bits));
    const auto shift = exponent > bits ? 0 : checked_cast<uint8_t>(bits - exponent);
    const auto postShift = exponent > bits ? checked_cast<int8_t>(bits - exponent) : 0;

    return std::make_tuple(mult, shift, postShift);
}

class QuantizationApproximation {
public:
    QuantizationApproximation(vpux::VPU::ArchKind architecture, double target);

    int64_t mult() const;
    int64_t shift() const;
    int64_t postShift() const;
    void setMult(uint16_t mult);
    void setShift(uint8_t shift);

private:
    uint16_t _mult;
    uint8_t _shift;
    int8_t _postShift;
};

class EltwiseQuantizationApproximation {
public:
    EltwiseQuantizationApproximation(vpux::VPU::ArchKind architecture, double input1Target, double input2Target,
                                     double outputTarget);

    QuantizationApproximation input1() const;
    QuantizationApproximation input2() const;
    QuantizationApproximation output() const;

private:
    QuantizationApproximation _input1;
    QuantizationApproximation _input2;
    QuantizationApproximation _output;
};

class PReLUApproximation {
public:
    PReLUApproximation(vpux::VPU::ArchKind architecture, double alpha);

    int64_t mult() const;
    int64_t shift() const;

private:
    // VPUX37XX mult is uint16_t - using int32_t as common storage
    int32_t _mult;
    uint8_t _shift;
};

std::pair<int64_t, int64_t> getClampValuesForQuantizedOps(std::pair<double, double> realMinMax,
                                                          mlir::quant::QuantizedType outElemQType,
                                                          mlir::Type outElemType);

//
// FakeQuantize support
//

mlir::quant::QuantizedType getQuantizedType(mlir::Attribute lowConstAttr, mlir::Attribute highConstAttr,
                                            std::optional<int64_t> levels, std::optional<mlir::Type> lowFpType,
                                            mlir::FloatType realType, bool isSigned, mlir::Location loc,
                                            IE::AutoBroadcastType broadcast = IE::AutoBroadcastType::NONE_OR_EXPLICIT,
                                            bool ignoreZPCheck = false, const Logger& log = Logger::global());

void getFakeQuantParams(mlir::quant::UniformQuantizedType qElemType, int64_t& levels, float& rMin, float& rMax);

void getFakeQuantParams(mlir::quant::UniformQuantizedPerAxisType qElemType, int64_t& levels,
                        SmallVectorImpl<float>& rMinVals, SmallVectorImpl<float>& rMaxVals);

void getFakeQuantParams(vpux::NDTypeInterface qType, int64_t& levels, mlir::RankedTensorType& attrType,
                        mlir::DenseElementsAttr& rMinAttr, mlir::DenseElementsAttr& rMaxAttr);

std::tuple<double, int64_t> calcScaleAndZeroPoint(int64_t qMin, int64_t qMax, double rMin, double rMax);
std::tuple<int64_t, int64_t, mlir::Type> getStorageParams(mlir::MLIRContext* ctx, int64_t levels, bool isSigned);
std::tuple<int64_t, int64_t, mlir::Type> getStorageParams(mlir::MLIRContext* ctx, mlir::Type lowFpType);
mlir::FailureOr<std::tuple<float, float>> getFp8Range(mlir::Type lowFpType);

/// Returns whether lowVals and highVals represet correct quantization range
/// specified by quantization levels and sign.
template <typename Range>
bool isLowPrecisionTypeRange(mlir::MLIRContext* ctx, Range lowVals, Range highVals, int64_t levels, bool isSigned) {
    VPUX_THROW_UNLESS(lowVals.size() == highVals.size(), "Sizes of valLow and valHigh arrays are not equal: {0} != {1}",
                      lowVals.size(), highVals.size());

    int64_t qLow = 0;
    int64_t qHigh = 0;
    std::tie(qLow, qHigh, std::ignore) = getStorageParams(ctx, levels, isSigned);
    const auto fLow = checked_cast<float>(qLow);
    const auto fHigh = checked_cast<float>(qHigh);
    // In order to decide if FakeQuantize input constant need to be requantized it is needed to check the FakeQuantize
    // input range.
    // Quantized weights have the content in the low precision data type - I/U 16,8,4...,1. For example, U8 quantized
    // weights are stored in U8 constants. Because NPU compiler relies on legacy weights de-quantization representation
    // which is: Const(FP16/32)->FakeQuantize(inLow = 0, inHigh = 255, ...), the WeightsDequantizeToFakeQuantize pass is
    // required to be applied. After this pass weights constant is FP16/32 data type and its content is floating point
    // values from 0.0 to 255.0 - just a cast of the U8 values - work in progress to keep the values in low precision
    // storage type: E#107322. There are passes that alter the weights content or create artificial FakeQuantize
    // (example: ConvertSubtractToAdd) and modify also FakeQuantize input range, which will no longer match the low
    // precision storage type as it initially was. It is needed to treat also the case when FakeQuantize inLow ==
    // inHigh, this is a special use case when re-quantization is not needed.
    const auto isEqualToLowPrecisionTypeRange = [&](float lowVal, float highVal) -> bool {
        return (isFloatEqual(lowVal, fLow) && isFloatEqual(highVal, fHigh)) || isFloatEqual(lowVal, highVal);
    };

    for (size_t i = 0; i < lowVals.size(); ++i) {
        if (!isEqualToLowPrecisionTypeRange(lowVals[i], highVals[i])) {
            return false;
        }
    }
    return true;
}

//
// Dequantize support
//

inline float dequantize(int64_t qVal, double scale, int64_t zeroPoint) {
    return static_cast<float>((qVal - zeroPoint) * scale);
}

//
// FakeQuantize support
//

float fakeQuantize(float inVal, float inLow, float inHigh, float qLow, float qHigh, float fLevels);

// Broadcasting

template <typename T>
void broadcastRange(SmallVectorImpl<T>& lowVals, SmallVectorImpl<T>& highVals, IE::AutoBroadcastType broadcast) {
    if (lowVals.size() == highVals.size()) {
        return;
    }
    if (broadcast == IE::AutoBroadcastType::NONE_OR_EXPLICIT) {
        return;
    }

    const auto numpyBroadcast = [](SmallVectorImpl<T>& smaller, SmallVectorImpl<T>& larger) {
        VPUX_THROW_UNLESS(smaller.size() == 1, "One of the dimensions should be 1 for broadcasting.");
        return SmallVector<T>(larger.size(), smaller[0]);
    };

    if (broadcast == IE::AutoBroadcastType::NUMPY) {
        if (lowVals.size() < highVals.size()) {
            lowVals = numpyBroadcast(lowVals, highVals);
        } else {
            highVals = numpyBroadcast(highVals, lowVals);
        }
        return;
    }

    VPUX_THROW("Unsupported broadcast type '{0}'", broadcast);
}

//
// Derive new UniformQuantizedType. Multiply scale by specified factor.
//

mlir::Type rescaleUniformQuantizedType(const mlir::Type tensorType, const double factor);

}  // namespace vpux
