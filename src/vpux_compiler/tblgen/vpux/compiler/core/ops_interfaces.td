//
// Copyright (C) 2022 Intel Corporation.
// SPDX-License-Identifier: Apache 2.0
//

#ifndef VPUX_COMPILER_CORE_OPS_INTERFACES
#define VPUX_COMPILER_CORE_OPS_INTERFACES

include "mlir/IR/OpBase.td"

//
// MultiViewOpInterface
//

def MultiViewOpInterface : OpInterface<"MultiViewOpInterface"> {
    let description = [{
        An extended version of view-like operation.
        It allows to define several resulting views in single operation.
    }];

    let cppNamespace = "vpux";

    let methods = [
        InterfaceMethod<
            "The source buffer from which the corresponding view is created, NULL if the result is not a view",
            "mlir::Value", "getViewSource", (ins "ptrdiff_t":$resultInd)
        >
    ];
}

//
// GroupedViewOpInterface
//

def GroupedViewOpInterface : OpInterface<"GroupedViewOpInterface"> {
    let description = [{
        An extended version of view-like operation.
        It allows grouping several buffers into a resulting view.
    }];
    let cppNamespace = "vpux";

    let methods = [
        InterfaceMethod<
        "Returns the source buffers from which the view is created.",
        "mlir::ValueRange", "getViewSources">
    ];
}

//
// DeclarationOp
//

def DeclarationOp : NativeOpTrait<"DeclarationOp"> {
    let cppNamespace = "vpux";
}

//
// DotInterface
//

def DotInterface : OpInterface<"DotInterface"> {
    let description = "Base interface for Dot graph generation";

    let cppNamespace = "vpux";

    let methods = [
        InterfaceMethod<
            "Get node color",
            "vpux::DotNodeColor", "getNodeColor", (ins),
            [{}],
            [{return vpux::DotNodeColor::NONE;}]
        >,

        InterfaceMethod<
            "If non empty overrides the default attributes in the dot graph",
            "bool", "printAttributes", (ins "llvm::raw_ostream&":$os, "llvm::StringRef":$head, "llvm::StringRef":$middle, "llvm::StringRef":$end),
            [{}],
            [{
                return false;
            }]
        >,

        InterfaceMethod<
            "Get the edge direction from the particular source",
            "DOT::EdgeDir", "getEdgeDirection", (ins "mlir::Operation*":$op),[{}],
            [{
                return DOT::EdgeDir::EDGE_NORMAL;
            }]
        >
    ];
}

#endif
