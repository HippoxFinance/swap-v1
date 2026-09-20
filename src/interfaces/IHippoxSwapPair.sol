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
    event FlashSwap(
        address indexed sender,
        address indexed recipient,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 amount0In,
        uint256 amount1In,
        address indexed dataProvider
    );
    /// @notice Emitted when the protocol fee is collected during a swap.
    event ProtocolFeeCollected(
        address indexed feeTo,
        uint256 amount0,
        uint256 amount1
    );
    function token0() external view returns (address);
    function token1() external view returns (address);
    /// @notice Address of the factory that created this pair.
    function factory() external view returns (address);
    function getReserves() external view returns (uint112, uint112);
    function mint(address to) external returns (uint256 liquidity);
    function burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
    /// @notice Executes a flash swap. Output tokens are sent to `to` first,
    ///         then `to` must call `flashSwapCallback` on the caller and repay
    ///         the input amount (plus fee) before the call returns.
    /// @param amount0Out Amount of token0 to send out.
    /// @param amount1Out Amount of token1 to send out.
    /// @param to Recipient of the output tokens and the callback target.
    /// @param data Arbitrary data passed to the callback.
    function flashSwap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
    // Roles, tax, and fee views.
    function creator() external view returns (address);
    function admin() external view returns (address);
    function taxBps() external view returns (uint256);
    function taxRecipient() external view returns (address);
    function feeNumerator() external view returns (uint256);
    /// @notice Protocol fee numerator applied on top of the AMM fee.
    ///         Read from the factory at swap time.
    function protocolFeeNumerator() external view returns (uint256);
    /// @notice Address that receives the protocol fee.
    ///         Read from the factory at swap time.
    function feeTo() external view returns (address);
    // Hook views.
    function hook() external view returns (address);
    // Oracle views.
    /// @notice Cumulative price of token0 in terms of token1, scaled by 2**112.
    function price0CumulativeLast() external view returns (uint256);
    /// @notice Cumulative price of token1 in terms of token0, scaled by 2**112.
    function price1CumulativeLast() external view returns (uint256);
    /// @notice Timestamp of the last oracle update.
    function blockTimestampLast() external view returns (uint40);
    /// @notice Returns cumulative prices and the last update timestamp in one call.
    function getCumulativePrices()
        external
        view
        returns (
            uint256 _price0CumulativeLast,
            uint256 _price1CumulativeLast,
            uint40 _blockTimestampLast
        );
    /// @notice Computes the time-weighted average price of tokenIn in terms of tokenOut.
    function consult(
        address tokenIn,
        uint256 amountIn,
        uint256 priceCumulativeLastThen,
        uint256 priceCumulativeLastNow,
        uint40 timeElapsed
    ) external view returns (uint256 amountOut);
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
        uint256 protocolFeeNumerator;
        address feeTo;
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
