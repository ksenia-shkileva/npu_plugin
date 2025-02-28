//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#include "vpux/compiler/dialect/IE/IR/ops.hpp"
#include "vpux/compiler/dialect/IE/transforms/passes.hpp"
#include "vpux/compiler/dialect/IE/utils/const_attributes.hpp"
#include "vpux/compiler/dialect/IE/utils/elem_type_info_utils.hpp"
#include "vpux/compiler/dialect/IE/utils/transpose_op_utils.hpp"
#include "vpux/compiler/utils/rewriter.hpp"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/Dialect/Quant/QuantTypes.h>
#include <mlir/IR/PatternMatch.h>
#include <mlir/Transforms/GreedyPatternRewriteDriver.h>

using namespace vpux;

namespace {

const int64_t SUPPORTED_RANK = 4;
const int8_t CHANNEL_ALIGNMENT = 16;

bool checkOrderCompatible(mlir::Operation* origOp, DimsOrder origOrder, DimsOrder parentOrder) {
    if (origOrder != parentOrder) {
        auto iface = mlir::dyn_cast<IE::LayoutInfoOpInterface>(origOp);
        if (iface == nullptr) {
            return false;
        }

        // Current logic (orderInfo.setInput) cannot set a new order with a different rank
        // e.g, 4D tensor -> AffineReshape -> 3D tensor -> 3D op  ===>  4D op -> 4D tensor -> AffineReshape -> 3D tensor
        // TODO: Fix E#79970 and remove the following conditional statement
        if (parentOrder.numDims() != origOrder.numDims()) {
            return false;
        }

        auto orderInfo = iface.getLayoutInfo();
        orderInfo.setInput(0, parentOrder);
        iface.inferLayoutInfo(orderInfo, /*seOpsEnabled=*/false, /*seExperimentalOpsEnabled=*/false);
        if (orderInfo.getInput(0) != parentOrder) {
            return false;
        }
        if (orderInfo.getOutput(0) != parentOrder) {
            return false;
        }
    }

    return true;
}

void updateOutputOrder(mlir::Value output, DimsOrder origOrder, DimsOrder parentOrder) {
    if (origOrder != parentOrder) {
        const auto newAddOutputType = output.getType().cast<vpux::NDTypeInterface>();
        const auto newType = newAddOutputType.changeDimsOrder(parentOrder);
        output.setType(newType);
    }
}

mlir::Value alignConstant(mlir::PatternRewriter& rewriter, mlir::Operation* parent, mlir::Value constInput) {
    return llvm::TypeSwitch<mlir::Operation*, mlir::Value>(parent)
            .Case<IE::AffineReshapeOp, IE::ReshapeOp>([&](auto origOp) {
                const auto constInputShape = getShape(constInput);
                const auto parentInputDimC = getShape(origOp.getInput())[Dims4D::Act::C];
                if (constInputShape.totalSize() != parentInputDimC) {
                    return mlir::Value();
                }

                SmallVector<int64_t> constShape(constInputShape.size(), 1);
                constShape[Dims4D::Act::C.ind()] = parentInputDimC;

                const auto constReshape = rewriter.createOrFold<IE::ReshapeOp>(
                        origOp->getLoc(), constInput, nullptr, false,
                        getIntArrayAttr(origOp->getContext(), ArrayRef(constShape)));

                const auto outOrder = DimsOrder::fromValue(constReshape);
                const auto inOrder = DimsOrder::fromValue(origOp.getInput());
                if (outOrder == inOrder) {
                    return constReshape;
                } else {
                    const auto newOrderMap = inOrder.toAffineMap(rewriter.getContext());
                    return rewriter.createOrFold<IE::ReorderOp>(origOp->getLoc(), constReshape, newOrderMap);
                }
            })
            .Case<IE::TransposeOp>([&](auto origOp) {
                const auto dstOrder = IE::deduceInverseOrder(origOp);
                const auto dstPerm = dstOrder.toAffineMap(origOp->getContext());
                const auto dstOrderAttr = mlir::AffineMapAttr::get(dstPerm);

                return rewriter.createOrFold<IE::TransposeOp>(origOp->getLoc(), constInput, nullptr, dstOrderAttr);
            })
            .Default([](mlir::Operation* op) -> mlir::Value {
                VPUX_THROW("Unsupported operation '{0}' at '{1}'", op->getName(), op->getLoc());
            });
}

bool isSingleValueBias(mlir::Value constInput) {
    auto declareOp = constInput.getDefiningOp<Const::DeclareOp>();
    if (declareOp == nullptr) {
        return false;
    }

    auto constShape = getShape(constInput).raw();
    auto hasNonTrivialDim = llvm::any_of(constShape, [](int64_t dim) {
        return dim != 1;
    });

    return !hasNonTrivialDim;
}

mlir::Value reshapeSingleValueConstant(mlir::PatternRewriter& rewriter, mlir::Location loc, int64_t numDims,
                                       mlir::Value constInput) {
    VPUX_THROW_UNLESS(isSingleValueBias(constInput), "Expext single value bias");
    auto ctx = rewriter.getContext();
    auto newConstShape = SmallVector<int64_t>(numDims, 1);
    auto reshapeConst =
            rewriter.create<IE::ReshapeOp>(loc, constInput, nullptr, false, getIntArrayAttr(ctx, newConstShape));
    return reshapeConst;
}

//
// SwapWithBias
//

class SwapWithBias final : public mlir::OpRewritePattern<IE::AddOp> {
public:
    SwapWithBias(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::AddOp>(ctx), _log(log) {
        setDebugName("SwapWithBias");
    }

public:
    mlir::LogicalResult matchAndRewrite(IE::AddOp origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult SwapWithBias::matchAndRewrite(IE::AddOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Found Add operation {1}", getDebugName(), origOp);

    bool lhsIsActivation = mlir::failed(IE::getConstParentOp(origOp.getInput1()));
    auto activationInput = lhsIsActivation ? origOp.getInput1() : origOp.getInput2();
    auto biasInput = lhsIsActivation ? origOp.getInput2() : origOp.getInput1();

    auto isEltwise = mlir::failed(IE::getConstParentOp(biasInput));
    if (isEltwise) {
        _log.trace("[{0}] Don't swap operations with Eltwise {1}", getDebugName(), origOp);
        return mlir::failure();
    }

    auto parentOp = activationInput.getDefiningOp();

    if (parentOp == nullptr) {
        return mlir::failure();
    }

    if (!mlir::isa<IE::ElemTypeInfoOpInterface>(parentOp)) {
        _log.trace("[{0}] Swapped operation {1} doesn't implement ElemTypeInfoOpInterface interface", getDebugName(),
                   *parentOp);
        return mlir::failure();
    }

    if (!parentOp->hasOneUse()) {
        _log.trace("[{0}] Swapped operation {1} has more than one use", getDebugName(), *parentOp);
        return mlir::failure();
    }

    auto parentInput = parentOp->getOperand(0);
    const auto origOrder = DimsOrder::fromValue(activationInput);
    const auto parentOrder = DimsOrder::fromValue(parentInput);

    auto singleValueBias = isSingleValueBias(biasInput);

    // Only the following situations are considered for Bias Swap:
    // From: NCE Task -> AffineReshapeOp/ReshapeOp/TransposeOp -> Add
    // To:   NCE Task -> Add -> AffineReshapeOp/ReshapeOp/TransposeOp
    // So that Add can as bias and fuse into NCE Task
    //
    // Single value bias is a special case:
    // 1.Can be swapped with ConcatOp
    // 2.Always be order compatible with parent op
    if (!mlir::isa<IE::AffineReshapeOp, IE::ReshapeOp, IE::TransposeOp>(parentOp)) {
        if (!(mlir::isa<IE::ConcatOp>(parentOp) && singleValueBias)) {
            _log.trace("[{0}] Only support AffineReshapeOp, ReshapeOp and TransposeOp, but got {1}", getDebugName(),
                       *parentOp);
            return mlir::failure();
        }
        _log.trace("[{0}] Swap single value bias with ConcatOp {1}", getDebugName(), parentOp->getLoc());
    }

    if (!singleValueBias) {
        if (parentInput.getType().cast<vpux::NDTypeInterface>().getRank() != SUPPORTED_RANK) {
            _log.trace("[{0}] Swapped operation doesn't have rank {1}", getDebugName(), SUPPORTED_RANK);
            return mlir::failure();
        }

        if (!checkOrderCompatible(origOp, origOrder, parentOrder)) {
            return mlir::failure();
        }
    }

    rewriter.startOpModification(parentOp);
    rewriter.setInsertionPoint(parentOp);

    // Create new Add ops for each input of parent operation.
    for (auto& operand : parentOp->getOpOperands()) {
        mlir::Value newConstant;
        if (singleValueBias) {
            auto oprandShape = getShape(operand.get()).raw();
            newConstant = reshapeSingleValueConstant(rewriter, origOp->getLoc(), oprandShape.size(), biasInput);
        } else {
            // TODO: E#68168 check the layout info as we did for Sigmod/Relu/Tanh
            newConstant = alignConstant(rewriter, parentOp, biasInput);
        }
        if (newConstant == nullptr) {
            _log.trace("[{0}] Swapped operation {1} fails to align constant", getDebugName(), *parentOp);
            return mlir::failure();
        }

        auto newAddOp = rewriter.create<IE::AddOp>(origOp->getLoc(), operand.get(), newConstant,
                                                   origOp.getAutoBroadcast(), nullptr, nullptr);

        // The new add must have the same output element type as the original one
        const auto origAddOutputType = origOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
        auto newAddOutputType = newAddOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
        newAddOutputType = newAddOutputType.changeElemType(origAddOutputType.getElementType());
        newAddOp->getResult(0).setType(newAddOutputType);

        // Update input of Operation. NewAddOp -> parent Op.
        operand.set(newAddOp.getOutput());

        updateOutputOrder(newAddOp->getResult(0), origOrder, parentOrder);
    }

    // The input and output element type must be the same for AffineReshape/Transpose/Reshape after swap
    const auto parentInputType = parentOp->getOpOperand(0).get().getType().dyn_cast<vpux::NDTypeInterface>();
    const auto oldParentOpOutType = parentOp->getResult(0).getType().dyn_cast<vpux::NDTypeInterface>();
    const auto newParentOpOutType = oldParentOpOutType.changeElemType(parentInputType.getElementType());
    parentOp->getResult(0).setType(newParentOpOutType);

    // Remove old Add ops.
    rewriter.replaceOp(origOp, parentOp->getResults());

    // Rewrite done.
    rewriter.finalizeOpModification(parentOp);

    return mlir::success();
}

//
// SwapWithActivation
//

template <class Activation>
class SwapWithActivation final : public mlir::OpRewritePattern<Activation> {
public:
    SwapWithActivation(mlir::MLIRContext* ctx, Logger log, bool seOpsEnabled)
            : mlir::OpRewritePattern<Activation>(ctx), _log(log), _seOpsEnabled(seOpsEnabled) {
        this->setDebugName("SwapWithActivation");
    }

public:
    mlir::LogicalResult matchAndRewrite(Activation origOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
    bool _seOpsEnabled;
};

template <class Activation>
mlir::LogicalResult SwapWithActivation<Activation>::matchAndRewrite(Activation origOp,
                                                                    mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Found activation function {1}", this->getDebugName(), origOp);

    auto parentOp = origOp.getInput().getDefiningOp();

    if (parentOp == nullptr) {
        return mlir::failure();
    }

    const auto logCb = [&](const formatv_object_base& msg) {
        _log.trace("{0}", msg.str());
    };

    if (!vpux::IE::isSupportedElemTypeInfoCase(parentOp, _seOpsEnabled, logCb)) {
        return mlir::failure();
    }

    if (!mlir::isa<IE::ElemTypeInfoOpInterface>(parentOp) || mlir::isa<IE::LayerWithPostOpInterface>(parentOp) ||
        mlir::isa<IE::SliceOp>(parentOp) || mlir::isa<Activation>(parentOp)) {
        _log.trace("[{0}] Swapped operation {1} doesn't implement ElemTypeInfoOpInterface interface {0} or it is an "
                   "activation",
                   this->getDebugName(), parentOp);
        return mlir::failure();
    }

    if (!parentOp->hasOneUse()) {
        _log.trace("[{0}] Swapped operation {1} has more than one use", this->getDebugName(), parentOp);
        return mlir::failure();
    }

    for (mlir::Value parentInput : parentOp->getOperands()) {
        if (parentInput.getType().cast<vpux::NDTypeInterface>().getRank() != SUPPORTED_RANK) {
            _log.trace("[{0}] Swapped operation doesn't have rank {1}", this->getDebugName(), SUPPORTED_RANK);
            return mlir::failure();
        }
    }

    mlir::Value origOperand = origOp->getResult(0);
    const auto origOrder = origOperand.getType().cast<vpux::NDTypeInterface>().getDimsOrder();
    mlir::Value parentInput = parentOp->getOperand(0);
    const auto parentOrder = parentInput.getType().cast<vpux::NDTypeInterface>().getDimsOrder();

    if (!checkOrderCompatible(origOp, origOrder, parentOrder)) {
        return mlir::failure();
    }

    rewriter.startOpModification(parentOp);
    rewriter.setInsertionPoint(parentOp);

    const auto parentOpInputs = parentOp->getOperands();
    for (auto i : irange<size_t>(0, parentOpInputs.size())) {
        auto newActivation = rewriter.clone(*origOp);
        newActivation->setOperand(0, parentOpInputs[i]);
        newActivation->getOpResult(0).setType(parentOpInputs[i].getType());
        parentOp->getOpOperand(static_cast<uint32_t>(i)).set(newActivation->getResult(0));
    }

    rewriter.replaceOp(origOp, parentOp->getResults());

    rewriter.finalizeOpModification(parentOp);

    return mlir::success();
}

class SwapTanhSlice final : public mlir::OpRewritePattern<IE::TanhOp> {
public:
    SwapTanhSlice(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::TanhOp>(ctx), _log(log) {
        this->setDebugName("SwapOperationsPass::SwapTanhSlice");
    }

private:
    mlir::LogicalResult matchAndRewrite(IE::TanhOp originOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult SwapTanhSlice::matchAndRewrite(IE::TanhOp originOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("Got '{0}' at '{1}'", originOp->getName(), originOp->getLoc());
    auto sliceOp = originOp.getInput().getDefiningOp<IE::SliceOp>();
    if (sliceOp == nullptr) {
        return mlir::failure();
    }

    auto oldSliceType = sliceOp->getResult(0).getType().cast<vpux::NDTypeInterface>();
    auto oldLayerType = originOp->getResult(0).getType().cast<vpux::NDTypeInterface>();
    auto newType = oldLayerType.changeShape(sliceOp.getSource().getType().cast<vpux::NDTypeInterface>().getShape());

    const auto oldSliceShape = oldSliceType.getShape();
    const auto newLayerShape = newType.getShape();

    // Move tanH only when the slice is due to channel alignment X % 16 != 0
    if (oldSliceShape[Dims4D::Act::C] % CHANNEL_ALIGNMENT == 0) {
        return mlir::failure();
    }

    // In case when actual number of channels is less than 1/2 of the aligned channel value
    // Such cases avoid moving TanH as it would be computationally expensive operation and does not offer any gain
    // e.g. Actual channels: 3 Aligned Channels 16, we don't want to compute TanH with 16 Channels for such case
    if (oldSliceShape[Dims4D::Act::C] < newLayerShape[Dims4D::Act::C] / 2) {
        return mlir::failure();
    }

    auto newOp = rewriter.create<IE::TanhOp>(originOp.getLoc(), newType, sliceOp.getSource());
    auto newSlice = rewriter.replaceOpWithNewOp<IE::SliceOp>(
            originOp, newOp->getResult(0), sliceOp.getStaticOffsetsAttr(), sliceOp.getStaticSizesAttr());

    newSlice->getResult(0).setType(oldSliceType);

    return mlir::success();
}

//
// SwapExpandQuantizeCast
//
// Move the QuantizeCast before Expand
// to support the possible Expand-Copy optimization in the following passes
//   Expand                         QuantizeCast
//      |                                 |
// QuantizeCast              ->        Expand

class SwapExpandQuantizeCast final : public mlir::OpRewritePattern<IE::ExpandOp> {
public:
    SwapExpandQuantizeCast(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::ExpandOp>(ctx), _log(log) {
        this->setDebugName("SwapExpandQuantizeCast");
    }

private:
    mlir::LogicalResult matchAndRewrite(IE::ExpandOp expandOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult SwapExpandQuantizeCast::matchAndRewrite(IE::ExpandOp expandOp,
                                                            mlir::PatternRewriter& rewriter) const {
    _log.trace("[{0}] Got '{0}' at '{1}'", getDebugName(), expandOp->getName(), expandOp->getLoc());
    if (!expandOp->hasOneUse()) {
        return mlir::failure();
    }
    auto quantizeCastOp = mlir::dyn_cast<IE::QuantizeCastOp>(*expandOp.getOutput().getUsers().begin());
    if (quantizeCastOp == nullptr) {
        return mlir::failure();
    }
    auto quantizeCastOutputType = quantizeCastOp.getOutput().getType().cast<vpux::NDTypeInterface>();
    auto quantizeCastInputType = quantizeCastOp.getInput().getType().cast<vpux::NDTypeInterface>();
    auto isPerChannel = [](vpux::NDTypeInterface type) {
        return type.getElementType().isa<mlir::quant::UniformQuantizedPerAxisType>();
    };
    if (isPerChannel(quantizeCastInputType) || isPerChannel(quantizeCastOutputType)) {
        return mlir::failure();
    }
    auto log = _log.nest();
    log.trace("Got Expand-QuantizeCast pattern: {0} -> {1}", expandOp->getLoc(), quantizeCastOp->getLoc());
    // Swap Expand-QuantizeCast to QuantizeCast-Expand
    auto expandInput = expandOp.getInput();
    auto quantizeCastOutputElemType = quantizeCastOutputType.getElementType();
    auto newQuantizeCastOp =
            rewriter.create<IE::QuantizeCastOp>(quantizeCastOp->getLoc(), expandInput, quantizeCastOutputElemType);
    expandOp.setOperand(newQuantizeCastOp);
    expandOp.getOutput().setType(mlir::cast<mlir::RankedTensorType>(quantizeCastOutputType));
    quantizeCastOp->replaceAllUsesWith(expandOp);
    log.trace("Swapped the Expand-QuantizeCast pattern: {0} -> {1}", newQuantizeCastOp->getLoc(), expandOp->getLoc());
    return mlir::success();
}

//
// SwapTanhShapeCast
//

class SwapTanhShapeCast final : public mlir::OpRewritePattern<IE::TanhOp> {
public:
    SwapTanhShapeCast(mlir::MLIRContext* ctx, Logger log): mlir::OpRewritePattern<IE::TanhOp>(ctx), _log(log) {
        this->setDebugName("SwapOperationsPass::SwapTanhShapeCast");
    }

private:
    mlir::LogicalResult matchAndRewrite(IE::TanhOp originOp, mlir::PatternRewriter& rewriter) const final;

private:
    Logger _log;
};

mlir::LogicalResult SwapTanhShapeCast::matchAndRewrite(IE::TanhOp origOp, mlir::PatternRewriter& rewriter) const {
    _log.trace("Got '{0}' at '{1}'", origOp->getName(), origOp->getLoc());
    auto shapeCastOp = origOp.getInput().getDefiningOp<IE::ShapeCastOp>();
    if (shapeCastOp == nullptr) {
        return mlir::failure();
    }

    if (!shapeCastOp->hasOneUse()) {
        return mlir::failure();
    }

    auto newTanhOp =
            rewriter.create<IE::TanhOp>(origOp.getLoc(), shapeCastOp.getSource().getType(), shapeCastOp.getSource());
    auto outputType = origOp.getResult().getType().cast<NDTypeInterface>();
    rewriter.replaceOpWithNewOp<IE::ShapeCastOp>(origOp, outputType, newTanhOp.getResult(),
                                                 getIntArrayAttr(origOp.getContext(), outputType.getShape()));

    return mlir::success();
}

//
// SwapOperationsPass
//

class SwapOperationsPass final : public IE::SwapOperationsBase<SwapOperationsPass> {
public:
    explicit SwapOperationsPass(const bool seOpsEnabled, Logger log): _seOpsEnabled(seOpsEnabled) {
        Base::initLogger(log, Base::getArgumentName());
    }
    mlir::LogicalResult initialize(mlir::MLIRContext* ctx) final;

private:
    void safeRunOnFunc() final;

    bool _seOpsEnabled;
};

mlir::LogicalResult SwapOperationsPass::initialize(mlir::MLIRContext* ctx) {
    if (mlir::failed(Base::initialize(ctx))) {
        return mlir::failure();
    }

    // When this parameter has a value, it probably comes from LIT test.
    // Override the default
    if (seOpsEnabled.hasValue()) {
        _seOpsEnabled = seOpsEnabled.getValue();
    }

    return mlir::success();
}

void SwapOperationsPass::safeRunOnFunc() {
    auto& ctx = getContext();

    mlir::RewritePatternSet patterns(&ctx);
    patterns.add<SwapWithActivation<IE::ReLUOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithActivation<IE::SigmoidOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithActivation<IE::TanhOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithActivation<IE::ClampOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithActivation<IE::LeakyReluOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithActivation<IE::ExpOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithActivation<IE::GeluOp>>(&ctx, _log.nest(), _seOpsEnabled);
    patterns.add<SwapWithBias>(&ctx, _log.nest());
    // TODO: E#18651 Support ElemTypeInfoOpInterface for Slice
    patterns.add<SwapTanhSlice>(&ctx, _log.nest());
    patterns.add<SwapTanhShapeCast>(&ctx, _log.nest());
    patterns.add<SwapExpandQuantizeCast>(&ctx, _log.nest());

    auto func = getOperation();
    if (mlir::failed(applyPatternsAndFoldGreedily(func, std::move(patterns), getDefaultGreedyRewriteConfig()))) {
        signalPassFailure();
    }
}

}  // namespace

//
// createSwapOperationsPass
//

std::unique_ptr<mlir::Pass> vpux::IE::createSwapOperationsPass(const bool seOpsEnabled, Logger log) {
    return std::make_unique<SwapOperationsPass>(seOpsEnabled, log);
}
