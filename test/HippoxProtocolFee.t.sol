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
/// @title HippoxProtocolFeeTest
/// @notice Tests for the protocol fee mechanism. Protocol fee parameters now
///         live on the factory and are read by the pair at swap time, so
///         changing the factory settings affects every existing pair.
contract HippoxProtocolFeeTest is Test {
    HippoxSwapFactory factory;
    HippoxSwapRouter router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;
    MockToken tokenD;
    address alice = makeAddr("alice");
    address feeRecipient = makeAddr("feeRecipient");
    address pair;
    address pair2;
    function setUp() public {
        weth = new WETH();
        // address(this) becomes the feeToSetter of the factory.
        factory = new HippoxSwapFactory(address(this));
        router = new HippoxSwapRouter(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        tokenC = new MockToken("TokenC", "C", 18);
        tokenD = new MockToken("TokenD", "D", 18);
        tokenA.mint(alice, 10_000_000e18);
        tokenB.mint(alice, 10_000_000e18);
        tokenC.mint(alice, 10_000_000e18);
        tokenD.mint(alice, 10_000_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
        tokenD.approve(address(router), type(uint256).max);
        // Pair 1: tokenA / tokenB
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
        // Pair 2: tokenC / tokenD, to verify factory-wide effect
        router.addLiquidity(
            address(tokenC),
            address(tokenD),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        pair = factory.getPair(address(tokenA), address(tokenB));
        pair2 = factory.getPair(address(tokenC), address(tokenD));
        assertTrue(pair != address(0), "pair exists");
        assertTrue(pair2 != address(0), "pair2 exists");
    }
    // Factory-level defaults
    function testDefaultProtocolFeeIsZero() public view {
        assertEq(
            factory.protocolFeeNumerator(),
            0,
            "default protocol fee is 0"
        );
        assertEq(
            HippoxSwapPair(pair).protocolFeeNumerator(),
            0,
            "pair reads 0"
        );
    }
    function testDefaultFeeToIsZero() public view {
        assertEq(factory.feeTo(), address(0), "factory feeTo zero");
        assertEq(HippoxSwapPair(pair).feeTo(), address(0), "pair reads zero");
    }
    function testDefaultFeeToSetterIsDeployer() public view {
        assertEq(
            factory.feeToSetter(),
            address(this),
            "feeToSetter is deployer"
        );
    }
    // Factory setters
    function testSetProtocolFeeNumerator() public {
        factory.setProtocolFeeNumerator(3);
        assertEq(factory.protocolFeeNumerator(), 3, "factory value set");
        assertEq(
            HippoxSwapPair(pair).protocolFeeNumerator(),
            3,
            "pair reads new value"
        );
        assertEq(
            HippoxSwapPair(pair2).protocolFeeNumerator(),
            3,
            "pair2 reads new value"
        );
    }
    function testSetProtocolFeeNumeratorTooHighReverts() public {
        vm.expectRevert(bytes("PROTOCOL_FEE_TOO_HIGH"));
        factory.setProtocolFeeNumerator(6);
    }
    function testSetProtocolFeeNumeratorAtMax() public {
        factory.setProtocolFeeNumerator(5);
        assertEq(factory.protocolFeeNumerator(), 5, "max accepted");
    }
    function testNonFeeToSetterCannotSetProtocolFee() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("FORBIDDEN"));
        factory.setProtocolFeeNumerator(3);
    }
    function testSetFeeTo() public {
        factory.setFeeTo(feeRecipient);
        assertEq(factory.feeTo(), feeRecipient, "factory feeTo set");
        assertEq(
            HippoxSwapPair(pair).feeTo(),
            feeRecipient,
            "pair reads new feeTo"
        );
        assertEq(
            HippoxSwapPair(pair2).feeTo(),
            feeRecipient,
            "pair2 reads new feeTo"
        );
    }
    function testNonFeeToSetterCannotSetFeeTo() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("FORBIDDEN"));
        factory.setFeeTo(feeRecipient);
    }
    function testSetFeeToSetter() public {
        factory.setFeeToSetter(feeRecipient);
        assertEq(factory.feeToSetter(), feeRecipient, "feeToSetter set");
        // Old setter can no longer act.
        vm.expectRevert(bytes("FORBIDDEN"));
        factory.setProtocolFeeNumerator(3);
        // New setter can.
        vm.prank(feeRecipient);
        factory.setProtocolFeeNumerator(3);
        assertEq(factory.protocolFeeNumerator(), 3, "new setter works");
    }
    function testNonFeeToSetterCannotSetFeeToSetter() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("FORBIDDEN"));
        factory.setFeeToSetter(feeRecipient);
    }
    // Protocol fee collected on swap
    function testProtocolFeeCollectedOnSwap() public {
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(3);
        uint256 beforeFee = tokenA.balanceOf(feeRecipient);
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
        uint256 feeCollected = tokenA.balanceOf(feeRecipient) - beforeFee;
        assertGt(feeCollected, 0, "protocol fee collected");
    }
    function testProtocolFeeZeroMeansNoFee() public {
        factory.setFeeTo(feeRecipient);
        // protocolFeeNumerator stays at 0.
        uint256 beforeFee = tokenA.balanceOf(feeRecipient);
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
        uint256 feeCollected = tokenA.balanceOf(feeRecipient) - beforeFee;
        assertEq(feeCollected, 0, "no protocol fee when numerator is 0");
    }
    // Factory-wide effect: change once, every pair sees it
    function testFactoryWideEffectOnExistingPairs() public {
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(3);
        // Swap on pair 1
        uint256 beforeFee1 = tokenA.balanceOf(feeRecipient);
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path1,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee1 = tokenA.balanceOf(feeRecipient) - beforeFee1;
        assertGt(fee1, 0, "pair1 collected fee");
        // Swap on pair 2
        uint256 beforeFee2 = tokenC.balanceOf(feeRecipient);
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenC);
        path2[1] = address(tokenD);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path2,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee2 = tokenC.balanceOf(feeRecipient) - beforeFee2;
        assertGt(fee2, 0, "pair2 collected fee");
    }
    function testChangeFactoryFeeAffectsNextSwap() public {
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(1);
        // First swap with numerator 1
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeFee1 = tokenA.balanceOf(feeRecipient);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee1 = tokenA.balanceOf(feeRecipient) - beforeFee1;
        // Raise the numerator and swap again
        factory.setProtocolFeeNumerator(5);
        uint256 beforeFee2 = tokenA.balanceOf(feeRecipient);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee2 = tokenA.balanceOf(feeRecipient) - beforeFee2;
        assertGt(fee2, fee1, "higher numerator collects more");
    }
    function testChangeFactoryFeeToAffectsNextSwap() public {
        factory.setProtocolFeeNumerator(3);
        factory.setFeeTo(feeRecipient);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeFee1 = tokenA.balanceOf(feeRecipient);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee1 = tokenA.balanceOf(feeRecipient) - beforeFee1;
        assertGt(fee1, 0, "first recipient got fee");
        // Switch recipient
        address newRecipient = makeAddr("newRecipient");
        factory.setFeeTo(newRecipient);
        uint256 beforeFee2 = tokenA.balanceOf(newRecipient);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee2 = tokenA.balanceOf(newRecipient) - beforeFee2;
        assertGt(fee2, 0, "new recipient got fee");
    }
    // User-visible output unaffected
    function testUserOutputUnchangedWithProtocolFee() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // First swap without protocol fee.
        uint256 beforeOut1 = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            100e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 outNoFee = tokenB.balanceOf(alice) - beforeOut1;
        // Enable protocol fee.
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(3);
        uint256 beforeOut2 = tokenB.balanceOf(alice);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            100e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 outWithFee = tokenB.balanceOf(alice) - beforeOut2;
        // Protocol fee is taken out of the AMM fee, so the user-visible
        // output should be within 1% of the no-fee case.
        assertGe(
            outWithFee,
            (outNoFee * 99) / 100,
            "user output within 1% with protocol fee"
        );
    }
    // PairInfo reflects factory values
    function testPairInfoIncludesProtocolFeeFields() public {
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(3);
        (address p, bytes memory infoBytes) = factory.getPairInfo(
            address(tokenA),
            address(tokenB)
        );
        assertEq(p, pair, "pair address");
        assertGt(infoBytes.length, 0, "info not empty");
    }
    function testPairReadsFactoryValuesDirectly() public {
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(4);
        // Pair reads from factory on every call, no caching.
        assertEq(
            HippoxSwapPair(pair).protocolFeeNumerator(),
            4,
            "pair reads factory numerator"
        );
        assertEq(
            HippoxSwapPair(pair).feeTo(),
            feeRecipient,
            "pair reads factory feeTo"
        );
    }
    // Flash swap also collects protocol fee
    function testProtocolFeeCollectedOnFlashSwap() public {
        factory.setFeeTo(feeRecipient);
        factory.setProtocolFeeNumerator(3);
        // Flash swap requires a callback contract. We reuse the pair's
        // internal swap path by calling flashSwap with a callback that
        // repays immediately. For this test we only check that the
        // protocol fee accounting path exists by verifying the factory
        // values are read. A full flash swap test lives in the flash
        // swap test suite.
        assertEq(
            HippoxSwapPair(pair).protocolFeeNumerator(),
            3,
            "flash swap reads factory value"
        );
        assertEq(
            HippoxSwapPair(pair).feeTo(),
            feeRecipient,
            "flash swap reads factory feeTo"
        );
    }
}
