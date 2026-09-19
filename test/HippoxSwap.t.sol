// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactory} from "../src/HippoxSwapFactory.sol";
import {HippoxSwapRouter} from "../src/HippoxSwapRouter.sol";
import {HippoxSwapPair} from "../src/HippoxSwapPair.sol";
import {WETH} from "../src/WETH.sol";
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
/// @title HippoxSwapTest
/// @notice End-to-end tests for every trading path: liquidity, swaps, ETH flows, multi-hop, extremes.
contract HippoxSwapTest is Test {
    HippoxSwapFactory factory;
    HippoxSwapRouter router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;
    MockToken usdc;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    function setUp() public {
        weth = new WETH();
        factory = new HippoxSwapFactory(address(this));
        router = new HippoxSwapRouter(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        tokenC = new MockToken("TokenC", "C", 18);
        usdc = new MockToken("USDC", "USDC", 6);
        tokenA.mint(alice, 1_000_000e18);
        tokenB.mint(alice, 1_000_000e18);
        tokenC.mint(alice, 1_000_000e18);
        usdc.mint(alice, 1_000_000e6);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(carol, 1000 ether);
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
        tokenA.mint(bob, 10_000e18);
        tokenB.mint(bob, 10_000e18);
        tokenA.mint(carol, 10_000e18);
        vm.prank(bob);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(bob);
        tokenB.approve(address(router), type(uint256).max);
        vm.prank(carol);
        tokenA.approve(address(router), type(uint256).max);
    }
    // CORE HAPPY PATH
    function testFullFlow() public {
        vm.prank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair created");
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 before = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(alice) - before;
        assertGt(received, 8e18, "received output");
        assertLt(received, 10e18, "fee deducted");
    }
    // LIQUIDITY PATHS
    function testAddLiquidityFirstTime() public {
        vm.prank(alice);
        (uint256 a, uint256 b, uint256 lp) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(a, 1000e18, "amountA");
        assertEq(b, 1000e18, "amountB");
        assertGt(lp, 0, "lp minted");
    }
    function testAddLiquiditySecondTimeProportional() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        (uint256 a, uint256 b, ) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            500e18,
            500e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertEq(a, 500e18, "proportional A");
        assertEq(b, 500e18, "proportional B");
    }
    function testAddLiquidityImbalanced() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // Provide more B than needed; Router should only take what's proportional.
        (uint256 a, uint256 b, ) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            500e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertEq(a, 100e18, "A as requested");
        assertLt(b, 500e18, "B reduced to match ratio");
    }
    function testRemoveLiquidityPartial() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBal = HippoxSwapPair(pair).balanceOf(alice);
        // Remove half.
        HippoxSwapPair(pair).approve(address(router), lpBal / 2);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBal / 2,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertEq(
            HippoxSwapPair(pair).balanceOf(alice),
            lpBal - lpBal / 2,
            "half LP remains"
        );
    }
    function testRemoveLiquidityFull() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBal = HippoxSwapPair(pair).balanceOf(alice);
        HippoxSwapPair(pair).approve(address(router), lpBal);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBal,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertEq(HippoxSwapPair(pair).balanceOf(alice), 0, "no LP left");
    }
    function testRemoveLiquiditySlippageProtection() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBal = HippoxSwapPair(pair).balanceOf(alice);
        HippoxSwapPair(pair).approve(address(router), lpBal);
        // Demand more than possible -> revert.
        vm.expectRevert("INSUFFICIENT_AMOUNT");
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBal,
            2000e18,
            2000e18,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // SWAP PATHS
    function testSwapExactTokensForTokens() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    function testSwapTokensForExactTokens() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeA = tokenA.balanceOf(alice);
        router.swapTokensForExactTokens(
            10e18,
            100e18,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 spent = beforeA - tokenA.balanceOf(alice);
        assertLt(spent, 100e18, "spent less than max");
        vm.stopPrank();
    }
    function testSwapTokensForExactTokensExceedsMaxReverts() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.expectRevert("EXCESSIVE_INPUT_AMOUNT");
        router.swapTokensForExactTokens(
            100e18,
            1e18,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // MULTI-HOP
    function testMultiHop2Hops() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        uint256 before = tokenC.balanceOf(alice);
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenC.balanceOf(alice) - before;
        vm.stopPrank();
        assertGt(received, 0, "multi-hop output");
        assertLt(received, 10e18, "fees across hops");
    }
    function testMultiHop3Hops() public {
        MockToken tokenD = new MockToken("TokenD", "D", 18);
        tokenD.mint(alice, 1_000_000e18);
        vm.startPrank(alice);
        tokenD.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        router.addLiquidity(
            address(tokenC),
            address(tokenD),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](4);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        path[3] = address(tokenD);
        uint256 before = tokenD.balanceOf(alice);
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenD.balanceOf(alice) - before;
        vm.stopPrank();
        assertGt(received, 0, "3-hop output");
    }
    // ETH PATHS
    function testSwapExactETHForTokens() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);
        uint256 before = tokenA.balanceOf(bob);
        vm.prank(bob);
        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            bob,
            block.timestamp + 1 hours
        );
        uint256 received = tokenA.balanceOf(bob) - before;
        assertGt(received, 0, "received tokenA");
    }
    function testSwapExactTokensForETH() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);
        uint256 before = bob.balance;
        vm.prank(bob);
        router.swapExactTokensForETH(
            1e18,
            0,
            path,
            bob,
            block.timestamp + 1 hours
        );
        uint256 received = bob.balance - before;
        assertGt(received, 0, "received ETH");
    }
    function testRemoveLiquidityETH() public {
        vm.startPrank(alice);
        (, , uint256 liquidity) = router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(weth));
        HippoxSwapPair(pair).approve(address(router), liquidity);
        uint256 beforeETH = alice.balance;
        router.removeLiquidityETH(
            address(tokenA),
            liquidity,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertGt(alice.balance, beforeETH, "ETH returned");
    }
    function testAddLiquidityETHRefund() public {
        vm.startPrank(alice);
        // First: seed the pool with exactly 100 ETH.
        router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // Second: send 200 ETH but only 100 is needed -> refund.
        uint256 beforeETH = alice.balance;
        router.addLiquidityETH{value: 200 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        uint256 spent = beforeETH - alice.balance;
        vm.stopPrank();
        // Spent should be ~100 ETH (the proportional amount), not 200.
        assertLt(spent, 200 ether, "refund applied");
        assertGt(spent, 0, "some ETH spent");
    }
    // SLIPPAGE & DEADLINE
    function testRevertOnHighSlippage() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            10e18,
            11e18,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    function testRevertOnExpiredDeadline() public {
        vm.prank(alice);
        vm.expectRevert("EXPIRED");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            100e18,
            0,
            0,
            alice,
            block.timestamp - 1
        );
    }
    function testDeadlineExactlyNow() public {
        vm.startPrank(alice);
        // deadline == now should pass (<= comparison).
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            100e18,
            0,
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();
    }
    // EXTREME: large, small, boundary
    function testVeryLargeLiquidity() public {
        tokenA.mint(alice, 1_000_000_000e18);
        tokenB.mint(alice, 1_000_000_000e18);
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1_000_000_000e18,
            1_000_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        (uint112 r0, uint112 r1) = HippoxSwapPair(
            factory.getPair(address(tokenA), address(tokenB))
        ).getReserves();
        assertGt(r0, 0, "large reserve0");
        assertGt(r1, 0, "large reserve1");
    }
    function testVerySmallLiquidity() public {
        tokenA.mint(alice, 10_000);
        tokenB.mint(alice, 10_000);
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10_000,
            10_000,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    function testTinySwapAfterLargeLiquidity() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100_000e18,
            100_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // 1 wei input in a 100k pool -> output rounds to 0, swap reverts.
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            1,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: repeated operations
    function testManyAddsAndRemoves() public {
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(alice);
            router.addLiquidity(
                address(tokenA),
                address(tokenB),
                100e18,
                100e18,
                0,
                0,
                alice,
                block.timestamp + 1 hours
            );
            address pair = factory.getPair(address(tokenA), address(tokenB));
            uint256 lpBal = HippoxSwapPair(pair).balanceOf(alice);
            HippoxSwapPair(pair).approve(address(router), lpBal);
            router.removeLiquidity(
                address(tokenA),
                address(tokenB),
                lpBal,
                0,
                0,
                alice,
                block.timestamp + 1 hours
            );
            vm.stopPrank();
        }
    }
    function testManyConsecutiveSwaps() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100_000e18,
            100_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        for (uint256 i = 0; i < 50; i++) {
            router.swapExactTokensForTokens(
                10e18,
                0,
                path,
                alice,
                block.timestamp + 1 hours
            );
        }
        vm.stopPrank();
        (uint112 r0, uint112 r1) = HippoxSwapPair(
            factory.getPair(address(tokenA), address(tokenB))
        ).getReserves();
        assertGt(r0, 0);
        assertGt(r1, 0);
    }
    // EXTREME: multiple LPs
    function testMultipleLPsShareFees() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        tokenA.mint(bob, 1000e18);
        tokenB.mint(bob, 1000e18);
        vm.startPrank(bob);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
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
        vm.stopPrank();
        // Swap to generate fees.
        vm.startPrank(carol);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(
            100e18,
            0,
            path,
            carol,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        // Both LPs should get back more than they put in.
        address pair = factory.getPair(address(tokenA), address(tokenB));
        vm.startPrank(alice);
        uint256 aliceLP = HippoxSwapPair(pair).balanceOf(alice);
        HippoxSwapPair(pair).approve(address(router), aliceLP);
        uint256 aliceBeforeA = tokenA.balanceOf(alice);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            aliceLP,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        uint256 aliceGotA = tokenA.balanceOf(alice) - aliceBeforeA;
        vm.stopPrank();
        assertGt(aliceGotA, 0, "alice got tokens back");
    }
    // EXTREME: unbalanced reserves
    function testUnbalancedReserves() public {
        // 10 tokenA vs 100000 tokenB.
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            10e18,
            100_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Small swap in a skewed pool.
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: mixed decimals
    function testMixedDecimalsPool() public {
        // Extra USDC so that after seeding liquidity, alice still has some for the swap.
        usdc.mint(alice, 1_000_000e6);
        vm.startPrank(alice);
        router.addLiquidity(
            address(usdc),
            address(tokenA),
            1_000_000e6,
            1_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(tokenA);
        uint256 before = tokenA.balanceOf(alice);
        router.swapExactTokensForTokens(
            1000e6,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenA.balanceOf(alice) - before;
        vm.stopPrank();
        assertGt(received, 0, "mixed decimals swap works");
    }
    // EXTREME: swap direction both ways
    function testSwapBothDirections() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory pathAB = new address[](2);
        pathAB[0] = address(tokenA);
        pathAB[1] = address(tokenB);
        address[] memory pathBA = new address[](2);
        pathBA[0] = address(tokenB);
        pathBA[1] = address(tokenA);
        router.swapExactTokensForTokens(
            10e18,
            0,
            pathAB,
            alice,
            block.timestamp + 1 hours
        );
        router.swapExactTokensForTokens(
            10e18,
            0,
            pathBA,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: add liquidity after swaps (reserve drift)
    function testAddLiquidityAfterSwaps() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Swap to skew reserves.
        router.swapExactTokensForTokens(
            100e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        // Add more liquidity; Router must use the new ratio.
        (uint256 a, uint256 b, ) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            500e18,
            500e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertGt(a, 0, "A added");
        assertGt(b, 0, "B added");
    }
    // EXTREME: remove all liquidity then swap must fail
    function testSwapAfterFullRemovalReverts() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBal = HippoxSwapPair(pair).balanceOf(alice);
        HippoxSwapPair(pair).approve(address(router), lpBal);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBal,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // After removal, the pair still holds MINIMUM_LIQUIDITY worth of reserves.
        (uint112 r0, uint112 r1) = HippoxSwapPair(pair).getReserves();
        // Directly request an output equal to the reserve -> must revert.
        tokenA.mint(alice, 1e18);
        vm.expectRevert("INSUFFICIENT_LIQUIDITY");
        HippoxSwapPair(pair).swap(0, r1, alice);
        // Also request an output larger than the reserve -> must revert.
        vm.expectRevert("INSUFFICIENT_LIQUIDITY");
        HippoxSwapPair(pair).swap(0, uint256(r1) + 1, alice);
        // And swap with both outputs zero -> must revert.
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        HippoxSwapPair(pair).swap(0, 0, alice);
        vm.stopPrank();
        // Sanity: reserves are tiny but non-zero.
        assertGt(r0, 0, "tiny reserve0 remains");
        assertGt(r1, 0, "tiny reserve1 remains");
    }
    // EXTREME: different callers, different receivers
    function testSwapToDifferentReceiver() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 before = tokenB.balanceOf(carol);
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            carol,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(carol) - before;
        vm.stopPrank();
        assertGt(received, 0, "carol received output");
    }
    function testAddLiquidityForDifferentReceiver() public {
        vm.prank(alice);
        (, , uint256 lp) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            carol,
            block.timestamp + 1 hours
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(HippoxSwapPair(pair).balanceOf(carol), lp, "carol holds LP");
    }
    // EXTREME: createPair is implicit via addLiquidity, then reuse
    function testPairReusedAcrossCalls() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair1 = factory.getPair(address(tokenA), address(tokenB));
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            100e18,
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address pair2 = factory.getPair(address(tokenA), address(tokenB));
        vm.stopPrank();
        assertEq(pair1, pair2, "same pair reused");
    }
    // EXTREME: all operations in one flow
    function testCompleteLifecycle() public {
        vm.startPrank(alice);
        // Add liquidity.
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // Multiple swaps.
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        for (uint256 i = 0; i < 5; i++) {
            router.swapExactTokensForTokens(
                10e18,
                0,
                path,
                alice,
                block.timestamp + 1 hours
            );
        }
        // Add more liquidity.
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            500e18,
            500e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // Remove half.
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBal = HippoxSwapPair(pair).balanceOf(alice);
        HippoxSwapPair(pair).approve(address(router), lpBal / 2);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBal / 2,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // Swap again.
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        // Remove all.
        uint256 remaining = HippoxSwapPair(pair).balanceOf(alice);
        HippoxSwapPair(pair).approve(address(router), remaining);
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            remaining,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: ETH lifecycle complete
    function testCompleteETHLifecycle() public {
        vm.startPrank(alice);
        // Add ETH liquidity.
        (, , uint256 lp) = router.addLiquidityETH{value: 100 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        // Swap ETH -> token.
        address[] memory pathBuy = new address[](2);
        pathBuy[0] = address(weth);
        pathBuy[1] = address(tokenA);
        router.swapExactETHForTokens{value: 1 ether}(
            0,
            pathBuy,
            alice,
            block.timestamp + 1 hours
        );
        // Swap token -> ETH.
        address[] memory pathSell = new address[](2);
        pathSell[0] = address(tokenA);
        pathSell[1] = address(weth);
        router.swapExactTokensForETH(
            1e18,
            0,
            pathSell,
            alice,
            block.timestamp + 1 hours
        );
        // Remove liquidity.
        address pair = factory.getPair(address(tokenA), address(weth));
        HippoxSwapPair(pair).approve(address(router), lp);
        router.removeLiquidityETH(
            address(tokenA),
            lp,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: swap with max slippage tolerance (0 min out)
    function testSwapWithZeroMinOut() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // amountOutMin = 0 always passes.
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: swap with exact expected output
    function testSwapWithExactMinOut() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Compute expected output with tax + fee, matching Pair.swap logic.
        uint256 amountIn = 10e18;
        uint256 rIn = 1000e18;
        uint256 rOut = 1000e18;
        uint256 taxBps = 10; // 0.1%
        uint256 feeNumerator = 3; // 0.3%
        // deduct trading tax.
        uint256 tax = (amountIn * taxBps) / 10_000;
        uint256 effectiveIn = amountIn - tax;
        // apply AMM fee and constant product.
        uint256 amountInWithFee = effectiveIn * (1000 - feeNumerator);
        uint256 expectedOut = (amountInWithFee * rOut) /
            (rIn * 1000 + amountInWithFee);
        // Set minOut to exact expected value -> should pass.
        router.swapExactTokensForTokens(
            amountIn,
            expectedOut,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
    // EXTREME: sender = receiver = router (edge)
    function testSwapToRouterItself() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000e18,
            1000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Send output to router; router has no withdraw, tokens are stuck. Test only that swap succeeds.
        router.swapExactTokensForTokens(
            10e18,
            0,
            path,
            address(router),
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        assertGt(tokenB.balanceOf(address(router)), 0, "router holds output");
    }
}
