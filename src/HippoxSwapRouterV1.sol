// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHippoxSwapFactoryV1} from "./interfaces/IHippoxSwapFactoryV1.sol";
import {IHippoxSwapPairV1} from "./interfaces/IHippoxSwapPairV1.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {HippoxSwapLibraryV1} from "./libs/HippoxSwapLibraryV1.sol";
/// @dev Minimal callback interface implemented by the Router to receive
///      flash swap callbacks from HippoxSwapPair.
interface IHippoxFlashSwapCallback {
    function flashSwapCallback(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 amount0In,
        uint256 amount1In,
        bytes calldata data
    ) external;
}
/// @title HippoxSwapRouterV1
/// @notice User-facing entry point. Handles slippage protection, ETH wrapping, multi-hop swaps, and flash swaps.
contract HippoxSwapRouterV1 is IHippoxFlashSwapCallback {
    using HippoxSwapLibraryV1 for address;
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
    /// @notice Adds liquidity. If the pair does not exist, it is created
    ///         without a hook (same behavior as before). Use the overload
    ///         `addLiquidityWithHook` to install a hook at creation time.
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
            amountBMin,
            address(0)
        );
        address pair = IHippoxSwapFactoryV1(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        liquidity = IHippoxSwapPairV1(pair).mint(to);
    }
    /// @notice Adds liquidity and creates the pair with a hook if it does not exist.
    /// @dev The hook is only used when the pair is being created in this call.
    ///      If the pair already exists, the hook parameter is ignored.
    function addLiquidityWithHook(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        address hook
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
            amountBMin,
            hook
        );
        address pair = IHippoxSwapFactoryV1(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);
        liquidity = IHippoxSwapPairV1(pair).mint(to);
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
        address pair = IHippoxSwapFactoryV1(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IHippoxSwapPairV1(pair).burn(to);
        (address token0, ) = HippoxSwapLibraryV1.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin && amountB >= amountBMin,
            "INSUFFICIENT_AMOUNT"
        );
    }
    // Liquidity: ETH/ERC20
    /// @notice Adds ETH/token liquidity. Creates the pair without a hook if missing.
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
            amountETHMin,
            address(0)
        );
        address pair = IHippoxSwapFactoryV1(factory).getPair(token, WETH);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(token).transferFrom(msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        IERC20(WETH).transfer(pair, amountETH);
        liquidity = IHippoxSwapPairV1(pair).mint(to);
        // Refund leftover ETH.
        if (msg.value > amountETH) {
            (bool ok, ) = msg.sender.call{value: msg.value - amountETH}("");
            require(ok, "ETH_REFUND_FAILED");
        }
    }
    /// @notice Adds ETH/token liquidity and creates the pair with a hook if missing.
    function addLiquidityETHWithHook(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        address hook
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
            amountETHMin,
            hook
        );
        address pair = IHippoxSwapFactoryV1(factory).getPair(token, WETH);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(token).transferFrom(msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        IERC20(WETH).transfer(pair, amountETH);
        liquidity = IHippoxSwapPairV1(pair).mint(to);
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
        address pair = IHippoxSwapFactoryV1(factory).getPair(token, WETH);
        require(pair != address(0), "PAIR_NOT_FOUND");
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IHippoxSwapPairV1(pair).burn(
            address(this)
        );
        (address token0, ) = HippoxSwapLibraryV1.sortTokens(token, WETH);
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
        amounts = HippoxSwapLibraryV1.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IERC20(path[0]).transferFrom(
            msg.sender,
            IHippoxSwapFactoryV1(factory).getPair(path[0], path[1]),
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
        amounts = HippoxSwapLibraryV1.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
        IERC20(path[0]).transferFrom(
            msg.sender,
            IHippoxSwapFactoryV1(factory).getPair(path[0], path[1]),
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
        amounts = HippoxSwapLibraryV1.getAmountsOut(factory, msg.value, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).deposit{value: amounts[0]}();
        IERC20(WETH).transfer(
            IHippoxSwapFactoryV1(factory).getPair(path[0], path[1]),
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
        amounts = HippoxSwapLibraryV1.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IERC20(path[0]).transferFrom(
            msg.sender,
            IHippoxSwapFactoryV1(factory).getPair(path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        (bool ok, ) = to.call{value: amounts[amounts.length - 1]}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }
    // Flash swap entry point
    /// @notice Executes a flash swap on a pair and forwards the callback to
    ///         the caller's contract. The caller must implement
    ///         IHippoxFlashSwapCallback and repay the pair before returning.
    function flashSwap(
        address pair,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external {
        require(pair != address(0), "ZERO_PAIR");
        IHippoxSwapPairV1(pair).flashSwap(
            amount0Out,
            amount1Out,
            msg.sender,
            data
        );
    }
    /// @notice Callback invoked by HippoxSwapPair during a flash swap.
    function flashSwapCallback(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 amount0In,
        uint256 amount1In,
        bytes calldata data
    ) external override {
        // Forward the callback to the original caller. The caller is
        // responsible for repaying the pair before this call returns.
        IHippoxFlashSwapCallback(sender).flashSwapCallback(
            sender,
            amount0Out,
            amount1Out,
            amount0In,
            amount1In,
            data
        );
    }
    // Extended read functions
    /// @notice Multi-hop quote including AMM fee and trading tax at each hop.
    function quote(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        return HippoxSwapLibraryV1.getAmountsOut(factory, amountIn, path);
    }
    /// @notice Batch multi-hop quotes.
    function quoteBatch(
        uint256[] calldata amountsIn,
        address[][] calldata paths
    ) external view returns (uint256[][] memory results) {
        require(amountsIn.length == paths.length, "LENGTH_MISMATCH");
        results = new uint256[][](amountsIn.length);
        for (uint256 i = 0; i < amountsIn.length; i++) {
            results[i] = HippoxSwapLibraryV1.getAmountsOut(
                factory,
                amountsIn[i],
                paths[i]
            );
        }
    }
    // Internal helpers
    /// @dev Creates the pair if missing. The pair's creator is set to msg.sender
    ///      (the actual end user calling the Router), not to the Router itself.
    ///      If `hook` is non-zero and the pair is being created, the pair is
    ///      created via createPairWithHook so that beforeInitialize and
    ///      afterInitialize actually fire. If the pair already exists, the
    ///      hook parameter is ignored.
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address hook
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (
            IHippoxSwapFactoryV1(factory).getPair(tokenA, tokenB) == address(0)
        ) {
            if (hook == address(0)) {
                IHippoxSwapFactoryV1(factory).createPair(
                    tokenA,
                    tokenB,
                    msg.sender
                );
            } else {
                IHippoxSwapFactoryV1(factory).createPairWithHook(
                    tokenA,
                    tokenB,
                    msg.sender,
                    hook
                );
            }
        }
        (uint256 reserveA, uint256 reserveB) = HippoxSwapLibraryV1.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = HippoxSwapLibraryV1.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = HippoxSwapLibraryV1.quote(
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
            (address token0, ) = HippoxSwapLibraryV1.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address nextPair = i < path.length - 2
                ? IHippoxSwapFactoryV1(factory).getPair(output, path[i + 2])
                : to;
            IHippoxSwapPairV1(
                IHippoxSwapFactoryV1(factory).getPair(input, output)
            ).swap(amount0Out, amount1Out, nextPair);
        }
    }
}
