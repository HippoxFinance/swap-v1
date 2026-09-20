// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IHippoxSwapPairV1} from "../interfaces/IHippoxSwapPairV1.sol";
/// @title HippoxSwapLibraryV1
/// @notice Helper functions for token sorting, reserve queries, and swap amount calculation.
library HippoxSwapLibraryV1 {
    uint256 internal constant FEE_DENOMINATOR = 1000;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        address pair = IHippoxSwapFactoryMinimal(factory).getPair(
            tokenA,
            tokenB
        );
        require(pair != address(0), "PAIR_NOT_FOUND");
        (uint112 reserve0, uint112 reserve1) = IHippoxSwapPairV1(pair)
            .getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));
    }
    function getFeeNumerator(address pair) internal view returns (uint256) {
        return IHippoxSwapPairV1(pair).feeNumerator();
    }
    function getTaxBps(address pair) internal view returns (uint256) {
        return IHippoxSwapPairV1(pair).taxBps();
    }
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }
    /// @notice Given input amount, reserves, fee numerator, and tax bps, returns net output.
    /// @dev Tax is applied to the input before the AMM fee, matching Pair.swap logic.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeNumerator,
        uint256 taxBps
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 tax = (amountIn * taxBps) / BPS_DENOMINATOR;
        uint256 effectiveIn = amountIn - tax;
        uint256 amountInWithFee = effectiveIn *
            (FEE_DENOMINATOR - feeNumerator);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }
    /// @notice Given output amount, reserves, fee numerator, and tax bps, returns required input.
    /// @dev Inverts the tax + fee formula. Tax is applied to the gross input.
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeNumerator,
        uint256 taxBps
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        // Solve for effectiveIn that yields amountOut under the AMM fee.
        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) *
            (FEE_DENOMINATOR - feeNumerator);
        uint256 effectiveIn = (numerator / denominator) + 1;
        // Gross input = effectiveIn / (1 - taxBps / BPS_DENOMINATOR), rounded up.
        amountIn =
            (effectiveIn * BPS_DENOMINATOR) /
            (BPS_DENOMINATOR - taxBps) +
            1;
    }
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory,
                path[i],
                path[i + 1]
            );
            address pair = IHippoxSwapFactoryMinimal(factory).getPair(
                path[i],
                path[i + 1]
            );
            uint256 feeNumerator = getFeeNumerator(pair);
            uint256 taxBps = getTaxBps(pair);
            amounts[i + 1] = getAmountOut(
                amounts[i],
                reserveIn,
                reserveOut,
                feeNumerator,
                taxBps
            );
        }
    }
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory,
                path[i - 1],
                path[i]
            );
            address pair = IHippoxSwapFactoryMinimal(factory).getPair(
                path[i - 1],
                path[i]
            );
            uint256 feeNumerator = getFeeNumerator(pair);
            uint256 taxBps = getTaxBps(pair);
            amounts[i - 1] = getAmountIn(
                amounts[i],
                reserveIn,
                reserveOut,
                feeNumerator,
                taxBps
            );
        }
    }
}
/// @dev Minimal factory interface used internally by the library.
interface IHippoxSwapFactoryMinimal {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}
