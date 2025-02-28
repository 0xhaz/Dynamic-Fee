// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {SwapFeeLibrary} from "../src/SwapFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {VolFeesHook} from "../src/VolFeesHook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {MockBrevisProof} from "../src/brevis/MockBrevisProof.sol";

contract TestVolFeesHook is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    bytes32 private constant VK_HASH = 0x179a48b8a2a08b246cd51cb7b78143db774a83ff75fad0d39cf0445e16773426;

    MockBrevisProof private brevisProofMock;
    VolFeesHook private hook;

    function setUp() public {
        // Deploy v4-core
        Deployers.deployFreshManagerAndRouters();
        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        // (currency0, currency1) = deployMintAndApprive2Currencies();
        Deployers.deployMintAndApprove2Currencies();

        // mock brevis proof contract for local testing
        brevisProofMock = new MockBrevisProof();

        // Deploy our hook with proper flags
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
        (, bytes32 salt) = HookMiner.find(
            address(this), flags, type(VolFeesHook).creationCode, abi.encode(manager, address(brevisProofMock))
        );

        // Deploy Hook
        hook = new VolFeesHook{salt: salt}(manager, address(brevisProofMock));

        // set brevis VK hash
        hook.setVkHash(VK_HASH);

        // Initialize a pool
        // Usually in 4th position you will have value of the fees (ie 3000)
        // We need to set it to 0x800000 by calling Dynamic Fees
        (key,) = initPool(currency0, currency1, hook, SwapFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1, ZERO_BYTES);

        // Add some liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 100_000 ether, 0), ZERO_BYTES
        );
    }

    // low vol test
    function test_Low_Vol_Low_Amt() public {
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        uint248 volatility = 20e18; // 20%

        // Simulate Brevis
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the max is 100%.
        assertEq(fee, 400);

        assertEq(swapDelta.amount0(), -1000410164165667268);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_Low_Vol_Mid_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        uint248 volatility = 20e18; // 20%

        // Simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the max is 100%.
        assertEq(fee, 832); // 8.3bps

        assertEq(swapDelta.amount0(), -10009327860790178430);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_Low_Vol_High_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 100 ether;
        uint248 volatility = 20e18; // 20%

        // Simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the max is 100%.
        assertEq(fee, 2200); // 22bps

        assertEq(swapDelta.amount0(), -100320805873020745742);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    //
    // mid vol tests
    //
    function test_Mid_Vol_Low_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        uint248 volatility = 60e18; // 60% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 800); // 8bps

        assertEq(swapDelta.amount0(), -1000810648618896118);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_Mid_Vol_Mid_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        uint248 volatility = 60e18; // 60% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 2097); // 20.9bps

        assertEq(swapDelta.amount0(), -10022016268124257570);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_Mid_Vol_High_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 100 ether;
        uint248 volatility = 60e18; // 60% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 6200); // 62bps

        assertEq(swapDelta.amount0(), -100724592574059267560);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_High_Vol_Low_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        uint248 volatility = 120e18; // 120% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 1400); // 14bps

        assertEq(swapDelta.amount0(), -1001411976867615663);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_High_Vol_Mid_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        uint248 volatility = 120e18; // 120% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 3994); // 39.9bps

        assertEq(swapDelta.amount0(), -10041104270466243177);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }

    function test_High_Vol_High_Amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 100 ether;
        uint248 volatility = 120e18; // 120% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 12200); // 1.22%

        assertEq(swapDelta.amount0(), -101336404231727171595);

        uint256 token1Output = currency1.balanceOfSelf() - balance1Before;
        assertEq(int256(swapDelta.amount1()), int256(token1Output));

        assertEq(int256(token1Output), amountSpecified);
    }
}
