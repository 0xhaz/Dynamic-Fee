// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapFeeLibrary} from "./SwapFeeLibrary.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BrevisApp} from "./brevis/BrevisApp.sol";
import {IBrevisProof} from "./brevis/IBrevisProof.sol";

contract VolFeesHook is BaseHook, BrevisApp, Ownable {
    using SwapFeeLibrary for uint24;

    event VolatilityUpdated(uint256 volatility);

    bytes32 public vkHash;

    uint256 public volatility;

    error MustUseDynamicFee();

    ////////////////////////// State Variables //////////////////////////
    uint24 public constant BASE_FEE = 200; // 0.2%

    // the commission on basis points that is paid to the hook to cover Brevis service costs
    uint24 public constant HOOK_COMMISSION = 100; // 0.1%

    // Initial BaseHook Parent Contract
    constructor(IPoolManager _poolManager, address brevisProof)
        BaseHook(_poolManager)
        BrevisApp(IBrevisProof(brevisProof))
        Ownable(msg.sender)
    {}

    ////////////////////////// Functions //////////////////////////

    // Permissions: Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // DYNAMIC_FEE_FLAG = 0x800000; // 24th bit
    // Check if the pool is enabled for dynamic fees
    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        // isDynamicFee: in Hooks >> from SwapFeeLibrary >> need to set to value of 0x800000
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata swapParams, bytes calldata)
        external
        view
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // calculate how much fee should be charged
        uint24 fee = calculateFee(abs(swapParams.amountSpecified));

        fee = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
    }

    // POC taking commissions to cover Brevis costs
    function takeCommission(PoolKey calldata key, IPoolManager.SwapParams calldata swapParams) internal {
        uint256 tokenAmount =
            swapParams.amountSpecified < 0 ? uint256(-swapParams.amountSpecified) : uint256(swapParams.amountSpecified);

        uint256 commissionAmt = Math.mulDiv(tokenAmount, HOOK_COMMISSION, 10_000);

        // determine inbound token based on 0 -> 1 or 1 -> 0 swap
        Currency inbound = swapParams.zeroForOne ? key.currency0 : key.currency1;

        // take the inbound token from the PoolManager, debt is paid by the swapper via the swap router
        // (inbound token is added to hook's reserves)
        poolManager.take(inbound, address(this), commissionAmt);
    }

    ////////////////////////// Brevis Functions //////////////////////////
    // BrevisQuery contract will call our callback once Brevis backend submits the proof
    function handleProofResult(bytes32, /*_requestId*/ bytes32 _vkHash, bytes calldata _circuitOutput)
        internal
        override
    {
        // we need to check if the verifying key that Brevis used to verify the proof generated by our circuit
        // is indeed our designated verifying key. This proves that the _circutOutput is indeed authentic and
        // generated by our circuit
        require(_vkHash == vkHash, "Invalid vkHash");

        volatility = decodeOutput(_circuitOutput);

        emit VolatilityUpdated(volatility);
    }

    // In app circuit we have:
    // api.OutputUint(248, vol)
    function decodeOutput(bytes calldata o) internal pure returns (uint256) {
        uint248 vol = uint248(bytes31(o[0:31])); // vol is output as a uint248 (31 bytes)
        return uint256(vol);
    }

    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }

    ////////////////////////// Helper Functions //////////////////////////
    function calculateFee(uint256 volume) internal view returns (uint24) {
        uint256 constant_factor = 1e26;
        uint256 variable_fee = sqrt(volume) * volatility / constant_factor;
        return uint24(BASE_FEE + variable_fee);
    }

    function abs(int256 x) private pure returns (uint256) {
        if (x >= 0) {
            return uint256(x);
        }

        return uint256(-x);
    }

    // Get Fee
    function getFee(int256 amnt) external view returns (uint24) {
        return calculateFee(abs(amnt));
    }

    function sqrt(uint256 x) public pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }
}
