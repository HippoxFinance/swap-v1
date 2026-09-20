// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxSwapPairV1} from "../src/HippoxSwapPairV1.sol";
import {WETH} from "../src/WETH.sol";
import {IHippoxSwapHookV1} from "../src/interfaces/IHippoxSwapHookV1.sol";
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
/// @dev Hook that records initialize callbacks.
contract InitHook is IHippoxSwapHookV1 {
    uint256 public beforeInitializeCount;
    uint256 public afterInitializeCount;
    function beforeInitialize(InitializeContext calldata) external override {
        beforeInitializeCount++;
    }
    function afterInitialize(InitializeContext calldata) external override {
        afterInitializeCount++;
    }
    function beforeModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external override {}
    function afterModifyLiquidity(
        ModifyLiquidityContext calldata
    ) external override {}
    function beforeSwap(SwapContext calldata) external override {}
    function afterSwap(SwapContext calldata) external override {}
    function name() external pure override returns (string memory) {
        return "InitHook";
    }
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
/// @title HippoxRouterHookTest
/// @notice Tests that the Router can create a pair with a hook via
///         addLiquidityWithHook, and that initialize hooks actually fire.
contract HippoxRouterHookTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    address alice = makeAddr("alice");
    function setUp() public {
        weth = new WETH();
        factory = new HippoxSwapFactoryV1(address(this));
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        tokenA.mint(alice, 10_000_000e18);
        tokenB.mint(alice, 10_000_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }
    function testAddLiquidityWithHookCreatesPairWithHook() public {
        InitHook hook = new InitHook();
        vm.prank(alice);
        router.addLiquidityWithHook(
            address(tokenA),
            address(tokenB),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours,
            address(hook)
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair created");
        assertEq(HippoxSwapPairV1(pair).hook(), address(hook), "hook installed");
    }
    function testInitializeHooksFireOnRouterCreatedPair() public {
        InitHook hook = new InitHook();
        vm.prank(alice);
        router.addLiquidityWithHook(
            address(tokenA),
            address(tokenB),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours,
            address(hook)
        );
        assertEq(hook.beforeInitializeCount(), 1, "beforeInitialize fired");
        assertEq(hook.afterInitializeCount(), 1, "afterInitialize fired");
    }
    function testAddLiquidityWithoutHookKeepsOldBehavior() public {
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
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair created");
        assertEq(HippoxSwapPairV1(pair).hook(), address(0), "no hook installed");
    }
    function testAddLiquidityWithHookOnExistingPairIgnoresHook() public {
        // First create pair without hook.
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
        InitHook hook = new InitHook();
        // Now add liquidity with a hook; pair already exists, so the hook is ignored.
        vm.prank(alice);
        router.addLiquidityWithHook(
            address(tokenA),
            address(tokenB),
            100e18,
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours,
            address(hook)
        );
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(
            HippoxSwapPairV1(pair).hook(),
            address(0),
            "hook ignored for existing pair"
        );
    }
    function testAddLiquidityETHWithHookCreatesPairWithHook() public {
        vm.deal(alice, 100 ether);
        InitHook hook = new InitHook();
        vm.prank(alice);
        router.addLiquidityETHWithHook{value: 100 ether}(
            address(tokenA),
            100e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours,
            address(hook)
        );
        address pair = factory.getPair(address(tokenA), address(weth));
        assertTrue(pair != address(0), "pair created");
        assertEq(HippoxSwapPairV1(pair).hook(), address(hook), "hook installed");
    }
}
