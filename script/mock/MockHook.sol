// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {IHippoxSwapHookV1} from "../../src/interfaces/IHippoxSwapHookV1.sol";
/// @title MockHook
/// @notice Minimal hook for local testing. Records the number of times each
///         callback was fired. Never reverts, never moves funds.
contract MockHook is IHippoxSwapHookV1 {
    uint256 public beforeInitializeCount;
    uint256 public afterInitializeCount;
    uint256 public beforeModifyLiquidityCount;
    uint256 public afterModifyLiquidityCount;
    uint256 public beforeSwapCount;
    uint256 public afterSwapCount;
    function beforeInitialize(InitializeContext calldata) external override {
        beforeInitializeCount++;
    }
    function afterInitialize(InitializeContext calldata) external override {
        afterInitializeCount++;
    }
    function beforeModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external override {
        beforeModifyLiquidityCount++;
    }
    function afterModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external override {
        afterModifyLiquidityCount++;
    }
    function beforeSwap(SwapContext calldata) external override {
        beforeSwapCount++;
    }
    function afterSwap(SwapContext calldata) external override {
        afterSwapCount++;
    }
    function name() external pure override returns (string memory) {
        return "MockHook";
    }
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
