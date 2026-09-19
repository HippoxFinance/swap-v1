// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/// @title IHippoxSwapHook
/// @notice Optional hook interface for HippoxSwapPair swaps.
/// @dev Hooks receive a single SwapContext struct to avoid stack-too-deep in
///      the pair's swap function. Hooks MUST NOT move funds, MUST NOT revert
///      the swap on failure, and MUST NOT reenter.
interface IHippoxSwapHook {
    /// @notice Full context of a swap, passed to both beforeSwap and afterSwap.
    /// @dev reserve0After / reserve1After are zero in beforeSwap and filled in
    ///      afterSwap. All other fields are populated for both calls.
    struct SwapContext {
        // Caller info.
        address sender;
        address txOrigin;
        // Token addresses.
        address token0;
        address token1;
        // Amounts.
        uint256 amount0In;
        uint256 amount1In;
        uint256 amount0Out;
        uint256 amount1Out;
        // Reserves.
        uint112 reserve0Before;
        uint112 reserve1Before;
        uint112 reserve0After;
        uint112 reserve1After;
        // Pair params.
        uint256 feeNumerator;
        uint256 taxBps;
        uint256 totalSupply;
        // Chain context.
        uint256 blockNumber;
        uint256 blockTimestamp;
        uint256 gasPrice;
        uint256 gasLeft;
    }
    /// @notice Called before the swap executes, after trading tax is deducted.
    /// @param ctx Full swap context. reserve0After / reserve1After are zero.
    /// amount0In / amount1In are post-tax (net) amounts.
    function beforeSwap(SwapContext calldata ctx) external;
    /// @notice Called after the swap completes and reserves are updated.
    /// @param ctx Full swap context with reserve0After / reserve1After filled.
    function afterSwap(SwapContext calldata ctx) external;
    function name() external view returns (string memory);
    function version() external view returns (string memory);
}
