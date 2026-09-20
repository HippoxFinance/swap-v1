// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxSwapPairV1} from "../src/HippoxSwapPairV1.sol";
import {HippoxOracleV1} from "../src/HippoxOracleV1.sol";
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
contract HippoxOracleReaderTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
    HippoxOracleV1 oracle;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    address alice = makeAddr("alice");
    address pair;
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
        oracle = new HippoxOracleV1(pair);
    }
    function testOraclePairSet() public view {
        assertEq(oracle.pair(), pair, "pair set");
    }
    function testMinElapsedTime() public view {
        assertEq(oracle.MIN_ELAPSED_TIME(), 30 minutes, "min elapsed");
    }
    function testUpdateWritesObservation() public {
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
        oracle.update();
        assertEq(oracle.observationsLength(), 1, "one observation");
    }
    function testUpdateRevertsOnSameTimestamp() public {
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
        oracle.update();
        vm.expectRevert(bytes("NO_TIME_ELAPSED"));
        oracle.update();
    }
    function testConsultRevertsOnShortWindow() public {
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
        oracle.update();
        vm.expectRevert(bytes("WINDOW_TOO_SHORT"));
        oracle.consult(address(tokenA), 1e18, 1 minutes);
    }
    function testConsultRevertsWithNotEnoughObservations() public {
        vm.expectRevert(bytes("NOT_ENOUGH_OBSERVATIONS"));
        oracle.consult(address(tokenA), 1e18, 1 hours);
    }
    function testConsultReturnsValue() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        oracle.update();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        oracle.update();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        oracle.update();
        uint256 amountOut = oracle.consult(address(tokenA), 1e18, 1 hours);
        assertGt(amountOut, 0, "consult returned value");
    }
    function testConsultRevertsOnInvalidToken() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 100 hours
        );
        oracle.update();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1e18,
            0,
            path,
            alice,
            block.timestamp + 100 hours
        );
        oracle.update();
        MockToken tokenC = new MockToken("TokenC", "C", 18);
        vm.expectRevert(bytes("INVALID_TOKEN"));
        oracle.consult(address(tokenC), 1e18, 1 hours);
    }
    function testCurrentCumulatives() public view {
        (uint256 p0, uint256 p1, uint40 ts) = oracle.currentCumulatives();
        assertEq(p0, 0, "p0 zero");
        assertEq(p1, 0, "p1 zero");
        assertEq(ts, uint40(block.timestamp), "timestamp set");
    }
}
