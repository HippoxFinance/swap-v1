// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHippoxSwapFactory} from "./interfaces/IHippoxSwapFactory.sol";
import {IHippoxSwapPair} from "./interfaces/IHippoxSwapPair.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {HippoxSwapLibrary} from "./libs/HippoxSwapLibrary.sol";
/// @title HippoxSwapRouter
/// @notice User-facing entry point. Handles slippage protection, ETH wrapping, and multi-hop swaps.
contract HippoxSwapRouter {
    using HippoxSwapLibrary for address;
    address public immutable factory;
    address public immutable WETH;
    modifier ensure(uint256 deadline) {
        require(block.timestamp <= deadline, "EXPIRED");
        _;
    }
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }
    receive() external payable {
        require(msg.sender == WETH, "ONLY_WETH");
    }
    // Liquidity: ERC20/ERC20
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = IHippoxSwapFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        liquidity = IHippoxSwapPair(pair).mint(to);
    }
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = IHippoxSwapFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IHippoxSwapPair(pair).burn(to);
        (address token0, ) = HippoxSwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin && amountB >= amountBMin,
            "INSUFFICIENT_AMOUNT"
        );
    }
    // Liquidity: ETH/ERC20
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = IHippoxSwapFactory(factory).getPair(token, WETH);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(token).transferFrom(msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        IERC20(WETH).transfer(pair, amountETH);
        liquidity = IHippoxSwapPair(pair).mint(to);
        // Refund leftover ETH.
        if (msg.value > amountETH) {
            (bool ok, ) = msg.sender.call{value: msg.value - amountETH}("");
            require(ok, "ETH_REFUND_FAILED");
        }
    }
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        address pair = IHippoxSwapFactory(factory).getPair(token, WETH);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IHippoxSwapPair(pair).burn(
            address(this)
        );
        (address token0, ) = HippoxSwapLibrary.sortTokens(token, WETH);
        (amountToken, amountETH) = token == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountToken >= amountTokenMin && amountETH >= amountETHMin,
            "INSUFFICIENT_AMOUNT"
        );
        IERC20(token).transfer(to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        (bool ok, ) = to.call{value: amountETH}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }
    // Swaps: ERC20/ERC20
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = HippoxSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IERC20(path[0]).transferFrom(
            msg.sender,
            IHippoxSwapFactory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = HippoxSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        IERC20(path[0]).transferFrom(
            msg.sender,
            IHippoxSwapFactory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }
    // Swaps: ETH/ERC20
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WETH, "INVALID_PATH");
        amounts = HippoxSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        IERC20(WETH).transfer(
            IHippoxSwapFactory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "INVALID_PATH");
        amounts = HippoxSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IERC20(path[0]).transferFrom(
            msg.sender,
            IHippoxSwapFactory(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        (bool ok, ) = to.call{value: amounts[amounts.length - 1]}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }
    // Extended read functions
    /// @notice Multi-hop quote including AMM fee and trading tax at each hop.
    /// @param amountIn Input amount.
    /// @param path Token path, length >= 2.
    /// @return amounts Output amounts at each hop. amounts[last] is the net user output.
    function quote(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        return HippoxSwapLibrary.getAmountsOut(factory, amountIn, path);
    }
    /// @notice Batch multi-hop quotes.
    /// @param amountsIn Input amounts, one per path.
    /// @param paths Array of token paths.
    /// @return results Array of output arrays, one per path.
    function quoteBatch(
        uint256[] calldata amountsIn,
        address[][] calldata paths
    ) external view returns (uint256[][] memory results) {
        require(amountsIn.length == paths.length, "LENGTH_MISMATCH");
        results = new uint256[][](amountsIn.length);
        for (uint256 i = 0; i < amountsIn.length; i++) {
            results[i] = HippoxSwapLibrary.getAmountsOut(
                factory,
                amountsIn[i],
                paths[i]
            );
        }
    }
    // Internal helpers
    /// @dev Creates the pair if missing. The pair's creator is set to msg.sender
    ///      (the actual end user calling the Router), not to the Router itself.
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (IHippoxSwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IHippoxSwapFactory(factory).createPair(tokenA, tokenB, msg.sender);
        }
        (uint256 reserveA, uint256 reserveB) = HippoxSwapLibrary.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = HippoxSwapLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = HippoxSwapLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                require(
                    amountAOptimal <= amountADesired &&
                        amountAOptimal >= amountAMin,
                    "INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address to
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = HippoxSwapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address nextPair = i < path.length - 2
                ? IHippoxSwapFactory(factory).getPair(output, path[i + 2])
                : to;
            IHippoxSwapPair(IHippoxSwapFactory(factory).getPair(input, output))
                .swap(amount0Out, amount1Out, nextPair);
        }
    }
}
