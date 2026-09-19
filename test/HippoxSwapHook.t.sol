// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactory} from "../src/HippoxSwapFactory.sol";
import {HippoxSwapRouter} from "../src/HippoxSwapRouter.sol";
import {HippoxSwapPair} from "../src/HippoxSwapPair.sol";
import {WETH} from "../src/WETH.sol";
import {IHippoxSwapHook} from "../src/interfaces/IHippoxSwapHook.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IHippoxSwapPair} from "../src/interfaces/IHippoxSwapPair.sol";
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
/// @dev Good hook that records the last SwapContext it received.
contract GoodHook is IHippoxSwapHook {
    uint256 public beforeCount;
    uint256 public afterCount;
    SwapContext internal _lastBefore;
    SwapContext internal _lastAfter;
    function beforeSwap(SwapContext calldata ctx) external override {
        beforeCount++;
        _lastBefore = ctx;
    }
    function afterSwap(SwapContext calldata ctx) external override {
        afterCount++;
        _lastAfter = ctx;
    }
    /// @notice Returns the full last beforeSwap context.
    function lastBefore() external view returns (SwapContext memory) {
        return _lastBefore;
    }
    /// @notice Returns the full last afterSwap context.
    function lastAfter() external view returns (SwapContext memory) {
        return _lastAfter;
    }
    function name() external pure override returns (string memory) {
        return "GoodHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @dev Hook that always reverts on beforeSwap.
contract RevertingBeforeHook is IHippoxSwapHook {
    function beforeSwap(SwapContext calldata) external pure override {
        revert("BEFORE_REVERT");
    }
    function afterSwap(SwapContext calldata) external override {}
    function name() external pure override returns (string memory) {
        return "RevertingBeforeHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @dev Hook that always reverts on afterSwap.
contract RevertingAfterHook is IHippoxSwapHook {
    function beforeSwap(SwapContext calldata) external override {}
    function afterSwap(SwapContext calldata) external pure override {
        revert("AFTER_REVERT");
    }
    function name() external pure override returns (string memory) {
        return "RevertingAfterHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @dev Hook that panics (division by zero) on both callbacks.
contract PanicHook is IHippoxSwapHook {
    function beforeSwap(SwapContext calldata) external pure override {
        uint256 x = 0;
        uint256 y = 1 / x;
        y;
    }
    function afterSwap(SwapContext calldata) external pure override {
        uint256 x = 0;
        uint256 y = 1 / x;
        y;
    }
    function name() external pure override returns (string memory) {
        return "PanicHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @dev Hook that tries to reenter swap. Should be blocked by nonReentrant.
contract ReentrantHook is IHippoxSwapHook {
    HippoxSwapPair public pair;
    bool public attempted;
    function setPair(address _pair) external {
        pair = HippoxSwapPair(_pair);
    }
    function beforeSwap(SwapContext calldata) external override {
        if (!attempted && address(pair) != address(0)) {
            attempted = true;
            try pair.swap(0, 1, address(this)) {} catch {}
        }
    }
    function afterSwap(SwapContext calldata) external override {}
    function name() external pure override returns (string memory) {
        return "ReentrantHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @title HippoxSwapHookTest
/// @notice Aggressive tests for the optional hook mechanism.
contract HippoxSwapHookTest is Test {
    HippoxSwapFactory factory;
    HippoxSwapRouter router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address pair;
    function setUp() public {
        weth = new WETH();
        factory = new HippoxSwapFactory(address(this));
        router = new HippoxSwapRouter(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        tokenA.mint(alice, 10_000_000e18);
        tokenB.mint(alice, 10_000_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
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
        vm.stopPrank();
        pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair exists");
    }
    // Default: no hook
    function testDefaultNoHook() public view {
        assertEq(HippoxSwapPair(pair).hook(), address(0), "no hook by default");
    }
    function testSwapWorksWithoutHook() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
    }
    // setHook permissions
    function testOnlyCreatorCanSetHook() public {
        GoodHook h = new GoodHook();
        vm.prank(bob);
        vm.expectRevert("ONLY_CREATOR");
        HippoxSwapPair(pair).setHook(address(h));
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        assertEq(HippoxSwapPair(pair).hook(), address(h));
    }
    function testCreatorCanClearHook() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        assertEq(HippoxSwapPair(pair).hook(), address(h));
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(0));
        assertEq(HippoxSwapPair(pair).hook(), address(0));
    }
    function testSetHookEmitsEvent() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        vm.expectEmit(true, true, false, false, pair);
        emit HippoxSwapPair.HookUpdated(address(0), address(h));
        HippoxSwapPair(pair).setHook(address(h));
    }
    // Good hook: receives full context
    function testGoodHookReceivesCorrectArgs() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h.beforeCount(), 1, "beforeSwap called once");
        assertEq(h.afterCount(), 1, "afterSwap called once");
        IHippoxSwapHook.SwapContext memory before = h.lastBefore();
        IHippoxSwapHook.SwapContext memory after_ = h.lastAfter();
        assertEq(before.amount0In, 999e18, "before amount0In post-tax");
        assertEq(after_.amount0In, 999e18, "after amount0In post-tax");
        assertEq(after_.amount0Out, 0, "amount0Out is zero for A->B");
        assertGt(after_.amount1Out, 0, "amount1Out recorded");
    }
    function testHookContextFieldsPopulated() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice, alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        IHippoxSwapHook.SwapContext memory ctx = h.lastAfter();
        assertEq(ctx.sender, address(router), "sender is router");
        assertEq(ctx.txOrigin, alice, "txOrigin is alice");
        assertEq(ctx.token0, address(tokenA), "token0");
        assertEq(ctx.token1, address(tokenB), "token1");
        assertGt(ctx.reserve0Before, 0, "reserve0Before");
        assertGt(ctx.reserve1Before, 0, "reserve1Before");
        assertGt(ctx.reserve0After, 0, "reserve0After");
        assertGt(ctx.reserve1After, 0, "reserve1After");
        assertEq(ctx.feeNumerator, 3, "feeNumerator");
        assertEq(ctx.taxBps, 10, "taxBps");
        assertGt(ctx.totalSupply, 0, "totalSupply");
        assertEq(ctx.blockNumber, block.number, "blockNumber");
        assertGt(ctx.blockTimestamp, 0, "blockTimestamp");
        assertGt(ctx.gasLeft, 0, "gasLeft");
    }
    // Hook failure must NOT block swap
    function testBeforeHookRevertDoesNotBlockSwap() public {
        RevertingBeforeHook h = new RevertingBeforeHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeBal = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(alice) - beforeBal;
        assertGt(received, 0, "swap succeeded despite beforeSwap revert");
    }
    function testAfterHookRevertDoesNotBlockSwap() public {
        RevertingAfterHook h = new RevertingAfterHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeBal = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(alice) - beforeBal;
        assertGt(received, 0, "swap succeeded despite afterSwap revert");
    }
    function testPanicHookDoesNotBlockSwap() public {
        PanicHook h = new PanicHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeBal = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(alice) - beforeBal;
        assertGt(received, 0, "swap succeeded despite panic hook");
    }
    // Reentrancy blocked
    function testReentrantHookBlocked() public {
        ReentrantHook h = new ReentrantHook();
        h.setPair(pair);
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeBal = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(alice) - beforeBal;
        assertGt(received, 0, "swap succeeded despite reentrancy attempt");
    }
    // Hook changes mid-flight
    function testHookChangeBetweenSwaps() public {
        GoodHook h1 = new GoodHook();
        GoodHook h2 = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h1));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h1.beforeCount(), 1);
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h2));
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h1.beforeCount(), 1, "h1 not called again");
        assertEq(h2.beforeCount(), 1, "h2 called");
    }
    function testClearHookStopsCallbacks() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h.beforeCount(), 1);
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(0));
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h.beforeCount(), 1, "no more callbacks after clear");
    }
    // Hook does not affect burn / mint
    function testHookNotCalledOnBurn() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        vm.startPrank(alice);
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
        assertEq(h.beforeCount(), 0, "burn does not trigger hook");
        assertEq(h.afterCount(), 0, "burn does not trigger hook");
    }
    function testHookNotCalledOnMint() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
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
        vm.stopPrank();
        assertEq(h.beforeCount(), 0, "mint does not trigger hook");
        assertEq(h.afterCount(), 0, "mint does not trigger hook");
    }
    // getPairInfo includes hook
    function testPairInfoIncludesHook() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        IHippoxSwapPair.PairInfo memory info = HippoxSwapPair(pair)
            .getPairInfo();
        assertEq(info.hook, address(h), "PairInfo.hook set");
    }
    // Hook is pure observer: cannot change reserves
    function testHookDoesNotChangeReserves() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        (uint112 r0Before, uint112 r1Before) = HippoxSwapPair(pair)
            .getReserves();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        (uint112 r0After, uint112 r1After) = HippoxSwapPair(pair).getReserves();
        assertGt(r0After, r0Before, "reserve0 increased");
        assertLt(r1After, r1Before, "reserve1 decreased");
    }
    // Many swaps with hook: state stays consistent
    function testManySwapsWithHook() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(alice);
            router.swapExactTokensForTokens(
                100e18,
                0,
                path,
                alice,
                block.timestamp + 1 hours
            );
        }
        assertEq(h.beforeCount(), 20, "20 beforeSwap calls");
        assertEq(h.afterCount(), 20, "20 afterSwap calls");
    }
    // Hook with max fee and tax still safe
    function testHookWithMaxFeeAndTax() public {
        GoodHook h = new GoodHook();
        vm.startPrank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        HippoxSwapPair(pair).setFeeNumerator(10);
        HippoxSwapPair(pair).setTaxBps(100);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h.beforeCount(), 1);
        assertEq(h.afterCount(), 1);
    }
    // Hook address zero is a no-op
    function testHookZeroIsNoOp() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
    }
    // Hook change does not require re-init
    function testHookChangeKeepsPairWorking() public {
        GoodHook h1 = new GoodHook();
        GoodHook h2 = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h1));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h2));
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        assertEq(h1.beforeCount(), 1);
        assertEq(h2.beforeCount(), 1);
    }
}
