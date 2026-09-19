// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/// @title IHippoxSwapPair
/// @notice Interface for the HippoxSwap pair contract.
interface IHippoxSwapPair {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112, uint112);
    function mint(address to) external returns (uint256 liquidity);
    function burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
    // Roles, tax, and fee views.
    function creator() external view returns (address);
    function admin() external view returns (address);
    function taxBps() external view returns (uint256);
    function taxRecipient() external view returns (address);
    function feeNumerator() external view returns (uint256);
    // Hook views.
    function hook() external view returns (address);
    // Extended read functions.
    /// @notice Aggregated snapshot of pair state.
    struct PairInfo {
        address token0;
        address token1;
        uint112 reserve0;
        uint112 reserve1;
        uint256 feeNumerator;
        uint256 feeDenominator;
        uint256 maxFeeNumerator;
        uint256 taxBps;
        uint256 maxTaxBps;
        uint256 bpsDenominator;
        address taxRecipient;
        uint256 totalSupply;
        address creator;
        address admin;
        uint256 minimumLiquidity;
        address hook;
    }
    /// @notice Returns a full snapshot of the pair's state in one call.
    function getPairInfo() external view returns (PairInfo memory);
    /// @notice Single-pool quote including AMM fee and trading tax.
    /// @param amountIn Input amount.
    /// @param tokenIn Input token address (must be token0 or token1).
    /// @return amountOut Net output after AMM fee and trading tax.
    function getAmountOut(
        uint256 amountIn,
        address tokenIn
    ) external view returns (uint256 amountOut);
}
