// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
/// @title IHippoxSwapHookV1
/// @notice Optional hook interface for HippoxSwapPair swaps and liquidity events.
/// @dev Hooks receive a single context struct to avoid stack-too-deep in
///      the pair's functions. Hooks MUST NOT move funds, MUST NOT revert
///      the main operation on failure, and MUST NOT reenter.
interface IHippoxSwapHookV1 {
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
    /// @notice Context passed to beforeInitialize and afterInitialize.
    /// @dev reserve0After / reserve1After are always zero here because the
    ///      pair has no reserves yet at initialization time.
    struct InitializeContext {
        // Caller info.
        address sender;
        address txOrigin;
        // Token addresses.
        address token0;
        address token1;
        // Roles.
        address creator;
        address admin;
        address taxRecipient;
        // Pair params.
        uint256 feeNumerator;
        uint256 taxBps;
        // Chain context.
        uint256 blockNumber;
        uint256 blockTimestamp;
        uint256 gasPrice;
        uint256 gasLeft;
    }
    /// @notice Context passed to beforeModifyLiquidity and afterModifyLiquidity.
    /// @dev For mint, liquidityDelta is positive. For burn, liquidityDelta is
    ///      represented by the amounts being withdrawn and the LP tokens burned.
    struct ModifyLiquidityContext {
        // Caller info.
        address sender;
        address txOrigin;
        // Token addresses.
        address token0;
        address token1;
        // Operation: true for mint (add), false for burn (remove).
        bool isMint;
        // Amounts added or removed.
        uint256 amount0;
        uint256 amount1;
        // LP tokens minted or burned.
        uint256 liquidity;
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
    /// @notice Called before the pair is initialized.
    /// @param ctx Initialization context.
    function beforeInitialize(InitializeContext calldata ctx) external;
    /// @notice Called after the pair is initialized.
    /// @param ctx Initialization context.
    function afterInitialize(InitializeContext calldata ctx) external;
    /// @notice Called before liquidity is added or removed.
    /// @param ctx Modify liquidity context. reserve0After / reserve1After are zero.
    function beforeModifyLiquidity(
        ModifyLiquidityContext calldata ctx
    ) external;
    /// @notice Called after liquidity is added or removed.
    /// @param ctx Modify liquidity context with reserve0After / reserve1After filled.
    function afterModifyLiquidity(ModifyLiquidityContext calldata ctx) external;
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
