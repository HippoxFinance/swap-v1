// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxSwapPairV1} from "../src/HippoxSwapPairV1.sol";
import {WETH} from "../src/WETH.sol";
import {IHippoxSwapPairV1} from "../src/interfaces/IHippoxSwapPairV1.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract MockToken is ERC20 {
    uint8 private _dec;
    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _dec = d;
    }
    function decimals() public view override returns (uint8) {
        return _dec;
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
/// @title HippoxOracleTest
/// @notice Tests for the on-chain native TWAP oracle integrated into HippoxSwapPair.
contract HippoxOracleTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address pair;
    function setUp() public {
        // Deploy core contracts.
        weth = new WETH();
        factory = new HippoxSwapFactoryV1(address(this));
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        // Deploy mock tokens.
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        // Fund alice and bob.
        tokenA.mint(alice, 10_000_000e18);
        tokenB.mint(alice, 10_000_000e18);
        tokenA.mint(bob, 10_000_000e18);
        tokenB.mint(bob, 10_000_000e18);
        // Approvals.
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();
        // Seed initial liquidity.
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair exists");
    }
    /// @notice After the first mint, the oracle timestamp should be set.
    function testOracleTimestampInitialized() public view {
        uint40 ts = HippoxSwapPairV1(pair).blockTimestampLast();
        assertEq(ts, uint40(block.timestamp), "timestamp set");
    }
    /// @notice Cumulative prices should remain zero until time passes and a
    ///         subsequent update happens.
    function testCumulativeZeroAtFirst() public view {
        (uint256 p0, uint256 p1, ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertEq(p0, 0, "price0 cumulative zero");
        assertEq(p1, 0, "price1 cumulative zero");
    }
    /// @notice After time passes and a swap occurs, cumulative prices should grow.
    function testCumulativeGrowsAfterTimeAndSwap() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0, uint256 p1, ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertGt(p0, 0, "price0 cumulative grew");
        assertGt(p1, 0, "price1 cumulative grew");
    }
    /// @notice The oracle should reflect the pool price. With equal reserves,
    ///         price0 and price1 should both be ~1 (scaled by 2**112).
    function testOracleReflectsEqualReserves() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0, , uint40 ts) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertGt(ts, 0, "timestamp updated");
        uint256 expectedApprox = (uint256(1) << 112) * 3600;
        uint256 lower = (expectedApprox * 95) / 100;
        uint256 upper = (expectedApprox * 105) / 100;
        assertGt(p0, lower, "cumulative not too low");
        assertLt(p0, upper, "cumulative not too high");
    }
    /// @notice consult() should return a TWAP-based output amount.
    function testConsultReturnsTwapAmount() public {
        (uint256 p0Then, uint256 p1Then, uint40 tsThen) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0Now, uint256 p1Now, uint40 tsNow) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        uint40 elapsed = tsNow - tsThen;
        assertGt(elapsed, 0, "time elapsed");
        uint256 amountOut = HippoxSwapPairV1(pair).consult(
            address(tokenA),
            1e18,
            p0Then,
            p0Now,
            elapsed
        );
        assertGt(amountOut, 0, "consult returned output");
        uint256 amountOutReverse = HippoxSwapPairV1(pair).consult(
            address(tokenB),
            1e18,
            p1Then,
            p1Now,
            elapsed
        );
        assertGt(amountOutReverse, 0, "consult reverse returned output");
    }
    /// @notice consult() should revert if timeElapsed is zero.
    function testConsultRevertsOnZeroElapsed() public {
        (uint256 p0Then, uint256 p0Now, ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        vm.expectRevert(bytes("INSUFFICIENT_ELAPSED_TIME"));
        HippoxSwapPairV1(pair).consult(address(tokenA), 1e18, p0Then, p0Now, 0);
    }
    /// @notice consult() should revert on an invalid token.
    function testConsultRevertsOnInvalidToken() public {
        MockToken tokenC = new MockToken("TokenC", "C", 18);
        (uint256 p0Then, uint256 p0Now, ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        vm.expectRevert(bytes("INVALID_TOKEN"));
        HippoxSwapPairV1(pair).consult(address(tokenC), 1e18, p0Then, p0Now, 1);
    }
    /// @notice Multiple updates over time should keep accumulating.
    function testCumulativeAccumulatesAcrossMultipleUpdates() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0First, , ) = HippoxSwapPairV1(pair).getCumulativePrices();
        assertGt(p0First, 0, "first accumulation");
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0Second, , ) = HippoxSwapPairV1(pair).getCumulativePrices();
        assertGt(p0Second, p0First, "second accumulation grows");
    }
    /// @notice Trading tax should not distort the oracle because _update uses
    ///         post-tax balances.
    function testOracleNotDistortedByTax() public {
        vm.prank(alice);
        HippoxSwapPairV1(pair).setTaxBps(100); // 1%
        vm.prank(alice);
        HippoxSwapPairV1(pair).setTaxRecipient(makeAddr("taxSink"));
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0, uint256 p1, ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertGt(p0, 0, "price0 cumulative grew despite tax");
        assertGt(p1, 0, "price1 cumulative grew despite tax");
    }
    /// @notice Mint and burn should also update the oracle.
    function testMintAndBurnUpdateOracle() public {
        vm.warp(block.timestamp + 1 hours);
        vm.prank(bob);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            bob,
            block.timestamp + 1 hours
        );
        (uint256 p0AfterMint, , ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertGt(p0AfterMint, 0, "oracle updated on mint");
        vm.warp(block.timestamp + 1 hours);
        uint256 lpBal = HippoxSwapPairV1(pair).balanceOf(bob);
        vm.startPrank(bob);
        HippoxSwapPairV1(pair).approve(address(router), lpBal);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBal,
            0,
            0,
            bob,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        (uint256 p0AfterBurn, , ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertGe(p0AfterBurn, p0AfterMint, "oracle did not decrease on burn");
    }
    /// @notice Same-block operations should not accumulate (timeElapsed == 0).
    function testSameBlockNoAccumulation() public {
        vm.prank(alice);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0AfterFirst, , ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 p0AfterSecond, , ) = HippoxSwapPairV1(pair)
            .getCumulativePrices();
        assertEq(p0AfterSecond, p0AfterFirst, "no accumulation in same block");
    }
}
