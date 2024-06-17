// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {PoolKey} from "v4-core/types/PoolKey.sol";

library SwapFeeLibrary {
    using SwapFeeLibrary for uint24;

    /// @notice Thrown when the static or dynamic fee on a pool is exceeds 100%
    error FeeTooLarge();

    uint24 public constant STATIC_FEE_MASK = 0x7FFFFF; // 23 bits
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000; // 24th bit

    // the swap fee is represented in hundredths of a bip, so the max is 100%.
    uint24 public constant MAX_SWAP_FEE = 1_000_000; // 100% in hundredths of a bip

    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function validate(uint24 self) internal pure {
        if (self >= MAX_SWAP_FEE) revert FeeTooLarge();
    }

    function getSwapFee(uint24 self) internal pure returns (uint24 swapFee) {
        // the initial fee for a dynamic fee pool is 0
        if (self.isDynamicFee()) return 0;
        swapFee = self & STATIC_FEE_MASK;
        swapFee.validate();
    }
}
