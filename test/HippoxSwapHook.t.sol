// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
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
/// @dev Good hook that records the last context it received for every callback.
contract GoodHook is IHippoxSwapHook {
    uint256 public beforeInitializeCount;
    uint256 public afterInitializeCount;
    uint256 public beforeModifyLiquidityCount;
    uint256 public afterModifyLiquidityCount;
    uint256 public beforeSwapCount;
    uint256 public afterSwapCount;
    InitializeContext internal _lastBeforeInitialize;
    InitializeContext internal _lastAfterInitialize;
    ModifyLiquidityContext internal _lastBeforeModifyLiquidity;
    ModifyLiquidityContext internal _lastAfterModifyLiquidity;
    SwapContext internal _lastBeforeSwap;
    SwapContext internal _lastAfterSwap;
    function beforeInitialize(
        InitializeContext calldata ctx
    ) external override {
        beforeInitializeCount++;
        _lastBeforeInitialize = ctx;
    }
    function afterInitialize(InitializeContext calldata ctx) external override {
        afterInitializeCount++;
        _lastAfterInitialize = ctx;
    }
    function beforeModifyLiquidity(
        ModifyLiquidityContext calldata ctx
    ) external override {
        beforeModifyLiquidityCount++;
        _lastBeforeModifyLiquidity = ctx;
    }
    function afterModifyLiquidity(
        ModifyLiquidityContext calldata ctx
    ) external override {
        afterModifyLiquidityCount++;
        _lastAfterModifyLiquidity = ctx;
    }
    function beforeSwap(SwapContext calldata ctx) external override {
        beforeSwapCount++;
        _lastBeforeSwap = ctx;
    }
    function afterSwap(SwapContext calldata ctx) external override {
        afterSwapCount++;
        _lastAfterSwap = ctx;
    }
    function lastBeforeInitialize()
        external
        view
        returns (InitializeContext memory)
    {
        return _lastBeforeInitialize;
    }
    function lastAfterInitialize()
        external
        view
        returns (InitializeContext memory)
    {
        return _lastAfterInitialize;
    }
    function lastBeforeModifyLiquidity()
        external
        view
        returns (ModifyLiquidityContext memory)
    {
        return _lastBeforeModifyLiquidity;
    }
    function lastAfterModifyLiquidity()
        external
        view
        returns (ModifyLiquidityContext memory)
    {
        return _lastAfterModifyLiquidity;
    }
    function lastBeforeSwap() external view returns (SwapContext memory) {
        return _lastBeforeSwap;
    }
    function lastAfterSwap() external view returns (SwapContext memory) {
        return _lastAfterSwap;
    }
    function name() external pure override returns (string memory) {
        return "GoodHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @dev Hook that reverts on every callback.
contract RevertingHook is IHippoxSwapHook {
    function beforeInitialize(
        InitializeContext calldata
    ) external pure override {
        revert("BEFORE_INIT_REVERT");
    }
    function afterInitialize(
        InitializeContext calldata
    ) external pure override {
        revert("AFTER_INIT_REVERT");
    }
    function beforeModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external pure override {
        revert("BEFORE_MODIFY_REVERT");
    }
    function afterModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external pure override {
        revert("AFTER_MODIFY_REVERT");
    }
    function beforeSwap(SwapContext calldata) external pure override {
        revert("BEFORE_SWAP_REVERT");
    }
    function afterSwap(SwapContext calldata) external pure override {
        revert("AFTER_SWAP_REVERT");
    }
    function name() external pure override returns (string memory) {
        return "RevertingHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @dev Hook that tries to reenter mint, burn, and swap.
contract ReentrantHook is IHippoxSwapHook {
    HippoxSwapPair public pair;
    bool public attemptedMint;
    bool public attemptedBurn;
    bool public attemptedSwap;
    function setPair(address _pair) external {
        pair = HippoxSwapPair(_pair);
    }
    function beforeInitialize(InitializeContext calldata) external override {}
    function afterInitialize(InitializeContext calldata) external override {}
    function beforeModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external override {
        if (!attemptedMint && address(pair) != address(0)) {
            attemptedMint = true;
            try pair.mint(address(this)) {} catch {}
        }
        if (!attemptedBurn && address(pair) != address(0)) {
            attemptedBurn = true;
            try pair.burn(address(this)) {} catch {}
        }
    }
    function afterModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external override {}
    function beforeSwap(SwapContext calldata) external override {
        if (!attemptedSwap && address(pair) != address(0)) {
            attemptedSwap = true;
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
/// @notice Tests for the extended hook mechanism, covering initialize,
///         modify liquidity, and swap callbacks.
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
        vm.expectRevert(bytes("ONLY_CREATOR"));
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
    /// @notice Verifies that setHook emits the HookUpdated event by scanning
    ///         the recorded logs for the matching event signature.
    function testSetHookEmitsEvent() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        vm.recordLogs();
        HippoxSwapPair(pair).setHook(address(h));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 expectedTopic = keccak256("HookUpdated(address,address)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedTopic) {
                found = true;
                break;
            }
        }
        assertTrue(found, "HookUpdated event emitted");
    }
    // Initialize hook
    function testInitializeHookNotCalledAfterTheFact() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        assertEq(h.beforeInitializeCount(), 0, "no retroactive beforeInit");
        assertEq(h.afterInitializeCount(), 0, "no retroactive afterInit");
    }
    function testInitializeHookFiresOnFreshPair() public {
        GoodHook h = new GoodHook();
        MockToken tokenC = new MockToken("TokenC", "C", 18);
        MockToken tokenD = new MockToken("TokenD", "D", 18);
        address freshPair = factory.createPairWithHook(
            address(tokenC),
            address(tokenD),
            alice,
            address(h)
        );
        assertTrue(freshPair != address(0), "fresh pair created");
        assertEq(
            HippoxSwapPair(freshPair).hook(),
            address(h),
            "hook installed"
        );
        assertEq(h.beforeInitializeCount(), 1, "beforeInitialize fired");
        assertEq(h.afterInitializeCount(), 1, "afterInitialize fired");
    }
    // Modify liquidity hooks
    function testModifyLiquidityHooksOnMint() public {
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
        assertEq(h.beforeModifyLiquidityCount(), 1, "beforeModifyLiquidity");
        assertEq(h.afterModifyLiquidityCount(), 1, "afterModifyLiquidity");
        IHippoxSwapHook.ModifyLiquidityContext memory before = h
            .lastBeforeModifyLiquidity();
        IHippoxSwapHook.ModifyLiquidityContext memory after_ = h
            .lastAfterModifyLiquidity();
        assertTrue(before.isMint, "isMint true");
        assertTrue(after_.isMint, "isMint true after");
        assertGt(before.amount0, 0, "amount0 positive");
        assertGt(before.amount1, 0, "amount1 positive");
        assertGt(before.liquidity, 0, "liquidity positive");
        assertEq(before.reserve0After, 0, "reserve0After zero before");
        assertGt(after_.reserve0After, 0, "reserve0After set after");
    }
    function testModifyLiquidityHooksOnBurn() public {
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
        assertEq(h.beforeModifyLiquidityCount(), 1, "beforeModifyLiquidity");
        assertEq(h.afterModifyLiquidityCount(), 1, "afterModifyLiquidity");
        IHippoxSwapHook.ModifyLiquidityContext memory before = h
            .lastBeforeModifyLiquidity();
        IHippoxSwapHook.ModifyLiquidityContext memory after_ = h
            .lastAfterModifyLiquidity();
        assertFalse(before.isMint, "isMint false");
        assertFalse(after_.isMint, "isMint false after");
        assertGt(before.amount0, 0, "amount0 positive");
        assertGt(before.amount1, 0, "amount1 positive");
        assertGt(before.liquidity, 0, "liquidity positive");
    }
    function testModifyLiquidityHooksNotCalledOnSwap() public {
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
        assertEq(h.beforeModifyLiquidityCount(), 0, "no modify hook on swap");
        assertEq(h.afterModifyLiquidityCount(), 0, "no modify hook on swap");
    }
    // Good hook: swap context still works
    function testGoodHookReceivesCorrectSwapArgs() public {
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
        assertEq(h.beforeSwapCount(), 1, "beforeSwap called once");
        assertEq(h.afterSwapCount(), 1, "afterSwap called once");
        IHippoxSwapHook.SwapContext memory before = h.lastBeforeSwap();
        IHippoxSwapHook.SwapContext memory after_ = h.lastAfterSwap();
        assertEq(before.amount0In, 999e18, "before amount0In post-tax");
        assertEq(after_.amount0In, 999e18, "after amount0In post-tax");
        assertEq(after_.amount0Out, 0, "amount0Out is zero for A->B");
        assertGt(after_.amount1Out, 0, "amount1Out recorded");
    }
    // Hook failure must NOT block the operation
    function testRevertingHookDoesNotBlockMint() public {
        RevertingHook h = new RevertingHook();
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
    }
    function testRevertingHookDoesNotBlockBurn() public {
        RevertingHook h = new RevertingHook();
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
    }
    function testRevertingHookDoesNotBlockSwap() public {
        RevertingHook h = new RevertingHook();
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
        assertGt(received, 0, "swap succeeded despite reverting hook");
    }
    // Reentrancy
    function testReentrantHookDoesNotBreakSwap() public {
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
    function testHookChangeBetweenOperations() public {
        GoodHook h1 = new GoodHook();
        GoodHook h2 = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h1));
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
        assertEq(h1.beforeModifyLiquidityCount(), 1);
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h2));
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
        assertEq(h1.beforeModifyLiquidityCount(), 1, "h1 not called again");
        assertEq(h2.beforeModifyLiquidityCount(), 1, "h2 called");
    }
    function testClearHookStopsCallbacks() public {
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
        assertEq(h.beforeModifyLiquidityCount(), 1);
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(0));
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
        assertEq(
            h.beforeModifyLiquidityCount(),
            1,
            "no more callbacks after clear"
        );
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
    // Many operations with hook: state stays consistent
    function testManyOperationsWithHook() public {
        GoodHook h = new GoodHook();
        vm.prank(alice);
        HippoxSwapPair(pair).setHook(address(h));
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
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
            router.swapExactTokensForTokens(
                100e18,
                0,
                path,
                alice,
                block.timestamp + 1 hours
            );
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
            vm.stopPrank();
        }
        assertEq(h.beforeModifyLiquidityCount(), 20, "10 mint + 10 burn");
        assertEq(h.afterModifyLiquidityCount(), 20, "10 mint + 10 burn");
        assertEq(h.beforeSwapCount(), 10, "10 swaps");
        assertEq(h.afterSwapCount(), 10, "10 swaps");
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
}
