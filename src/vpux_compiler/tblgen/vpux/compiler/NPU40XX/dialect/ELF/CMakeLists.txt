#
# Copyright (C) 2023 Intel Corporation.
# SPDX-License-Identifier: Apache 2.0
#

add_vpux_dialect(ELF)
add_vpux_ops_interface(ELF NPU40XX/dialect/ELF/)
add_vpux_attribute(ELF ENABLE_VPUX_ENUMS ENABLE_VPUX_ATTR)
add_vpux_pass(ELF ELF NPU40XX/dialect/ELF/)
