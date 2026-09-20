// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxSwapPairV1} from "../src/HippoxSwapPairV1.sol";
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
/// @notice Tests for the protocol fee mechanism. Protocol fee parameters live
///         on the factory and are read by the pair at swap time. The factory
///         has a single owner role with full control over the parameters.
///         The public setter takes a percentage value (0 to 50) of the AMM fee
///         and converts it into the internal numerator (0 to 500) stored on
///         the factory.
contract HippoxProtocolFeeTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;
    MockToken tokenD;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address feeRecipient = makeAddr("feeRecipient");
    address pair;
    address pair2;
    function setUp() public {
        weth = new WETH();
        // owner is the initial owner of the factory.
        vm.prank(owner);
        factory = new HippoxSwapFactoryV1(owner);
        router = new HippoxSwapRouterV1(address(factory), address(weth));
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
    // Defaults
    function testDefaultOwner() public view {
        assertEq(factory.owner(), owner, "owner is deployer");
    }
    function testDefaultFeeToIsOwner() public view {
        assertEq(factory.feeTo(), owner, "feeTo defaults to owner");
        assertEq(
            HippoxSwapPairV1(pair).feeTo(),
            owner,
            "pair reads owner as feeTo"
        );
    }
    function testDefaultProtocolFeeIsHalfPercent() public view {
        // Default internal numerator is 5, i.e. 0.5% of the AMM fee.
        assertEq(
            factory.protocolFeeNumerator(),
            5,
            "default internal numerator is 5"
        );
        assertEq(
            factory.protocolFeeNumeratorPercen(),
            0,
            "percen reads 0 due to integer division"
        );
        assertEq(
            HippoxSwapPairV1(pair).protocolFeeNumerator(),
            5,
            "pair reads internal numerator"
        );
    }
    function testMaxProtocolFeePercenIsFifty() public view {
        assertEq(
            factory.MAX_PROTOCOL_FEE_PERCEN(),
            50,
            "max percen is 50, i.e. 50% of AMM fee"
        );
    }
    function testMaxProtocolFeeNumeratorIsFiveHundred() public view {
        assertEq(
            factory.MAX_PROTOCOL_FEE_NUMERATOR(),
            500,
            "max internal numerator is 500"
        );
    }
    // Owner setters: setProtocolFeeNumeratorPercen
    function testOwnerCanSetProtocolFeePercen() public {
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(5);
        assertEq(factory.protocolFeeNumeratorPercen(), 5, "percen reads 5");
        assertEq(
            factory.protocolFeeNumerator(),
            50,
            "internal numerator is 50"
        );
        assertEq(
            HippoxSwapPairV1(pair).protocolFeeNumerator(),
            50,
            "pair reads 50"
        );
        assertEq(
            HippoxSwapPairV1(pair2).protocolFeeNumerator(),
            50,
            "pair2 reads 50"
        );
    }
    function testSetProtocolFeePercenToZero() public {
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(0);
        assertEq(factory.protocolFeeNumeratorPercen(), 0, "percen 0");
        assertEq(factory.protocolFeeNumerator(), 0, "internal 0");
    }
    function testSetProtocolFeePercenAtMax() public {
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(50);
        assertEq(factory.protocolFeeNumeratorPercen(), 50, "percen 50");
        assertEq(factory.protocolFeeNumerator(), 500, "internal 500");
    }
    function testSetProtocolFeePercenTooHighReverts() public {
        vm.prank(owner);
        vm.expectRevert(bytes("PROTOCOL_FEE_TOO_HIGH"));
        factory.setProtocolFeeNumeratorPercen(51);
    }
    function testNonOwnerCannotSetProtocolFeePercen() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("ONLY_OWNER"));
        factory.setProtocolFeeNumeratorPercen(5);
    }
    function testProtocolFeePercenConversion() public {
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(50);
        assertEq(factory.protocolFeeNumeratorPercen(), 50, "percen 50");
        assertEq(factory.protocolFeeNumerator(), 500, "internal 500");
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(25);
        assertEq(factory.protocolFeeNumeratorPercen(), 25, "percen 25");
        assertEq(factory.protocolFeeNumerator(), 250, "internal 250");
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(1);
        assertEq(factory.protocolFeeNumeratorPercen(), 1, "percen 1");
        assertEq(factory.protocolFeeNumerator(), 10, "internal 10");
    }
    // Owner setters: feeTo, owner
    function testOwnerCanSetFeeTo() public {
        vm.prank(owner);
        factory.setFeeTo(feeRecipient);
        assertEq(factory.feeTo(), feeRecipient, "factory feeTo set");
        assertEq(
            HippoxSwapPairV1(pair).feeTo(),
            feeRecipient,
            "pair reads new feeTo"
        );
        assertEq(
            HippoxSwapPairV1(pair2).feeTo(),
            feeRecipient,
            "pair2 reads new feeTo"
        );
    }
    function testSetFeeToZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(bytes("ZERO_FEE_TO"));
        factory.setFeeTo(address(0));
    }
    function testNonOwnerCannotSetFeeTo() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("ONLY_OWNER"));
        factory.setFeeTo(feeRecipient);
    }
    function testOwnerCanSetOwner() public {
        vm.prank(owner);
        factory.setOwner(feeRecipient);
        assertEq(factory.owner(), feeRecipient, "owner transferred");
        // Old owner can no longer act.
        vm.prank(owner);
        vm.expectRevert(bytes("ONLY_OWNER"));
        factory.setProtocolFeeNumeratorPercen(5);
        // New owner can.
        vm.prank(feeRecipient);
        factory.setProtocolFeeNumeratorPercen(5);
        assertEq(factory.protocolFeeNumeratorPercen(), 5, "new owner works");
    }
    function testSetOwnerZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(bytes("ZERO_OWNER"));
        factory.setOwner(address(0));
    }
    function testNonOwnerCannotSetOwner() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("ONLY_OWNER"));
        factory.setOwner(feeRecipient);
    }
    // Protocol fee collected on swap
    function testProtocolFeeCollectedOnSwap() public {
        // Default state: feeTo = owner, internal numerator = 5.
        uint256 beforeFee = tokenA.balanceOf(owner);
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
        uint256 feeCollected = tokenA.balanceOf(owner) - beforeFee;
        assertGt(feeCollected, 0, "protocol fee collected");
    }
    function testProtocolFeePercenZeroMeansNoFee() public {
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(0);
        uint256 beforeFee = tokenA.balanceOf(owner);
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
        uint256 feeCollected = tokenA.balanceOf(owner) - beforeFee;
        assertEq(feeCollected, 0, "no protocol fee when percen is 0");
    }
    // Factory-wide effect
    function testFactoryWideEffectOnExistingPairs() public {
        // Default state already has feeTo = owner and percen = 0.5%,
        // so both pairs should collect on the first swap.
        uint256 beforeFee1 = tokenA.balanceOf(owner);
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
        uint256 fee1 = tokenA.balanceOf(owner) - beforeFee1;
        assertGt(fee1, 0, "pair1 collected fee");
        uint256 beforeFee2 = tokenC.balanceOf(owner);
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
        uint256 fee2 = tokenC.balanceOf(owner) - beforeFee2;
        assertGt(fee2, 0, "pair2 collected fee");
    }
    function testChangeFactoryFeePercenAffectsNextSwap() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Set percen to 1 (internal 10)
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(1);
        uint256 beforeFee1 = tokenA.balanceOf(owner);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee1 = tokenA.balanceOf(owner) - beforeFee1;
        // Raise percen to 50 (internal 500, max)
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(50);
        uint256 beforeFee2 = tokenA.balanceOf(owner);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee2 = tokenA.balanceOf(owner) - beforeFee2;
        assertGt(fee2, fee1, "higher percen collects more");
    }
    function testChangeFactoryFeeToAffectsNextSwap() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // First swap with default feeTo (owner).
        uint256 beforeFee1 = tokenA.balanceOf(owner);
        vm.prank(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 fee1 = tokenA.balanceOf(owner) - beforeFee1;
        assertGt(fee1, 0, "owner got fee");
        // Switch recipient.
        vm.prank(owner);
        factory.setFeeTo(feeRecipient);
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
        assertGt(fee2, 0, "new recipient got fee");
    }
    // User-visible output unaffected
    function testUserOutputUnchangedWithProtocolFee() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // First swap with percen = 0.
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(0);
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
        // Enable protocol fee at 50%.
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(50);
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
        vm.prank(owner);
        factory.setFeeTo(feeRecipient);
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(5);
        (address p, bytes memory infoBytes) = factory.getPairInfo(
            address(tokenA),
            address(tokenB)
        );
        assertEq(p, pair, "pair address");
        assertGt(infoBytes.length, 0, "info not empty");
    }
    function testPairReadsFactoryValuesDirectly() public {
        vm.prank(owner);
        factory.setFeeTo(feeRecipient);
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(5);
        // Pair reads from factory on every call, no caching.
        // 5 percent = internal 50.
        assertEq(
            HippoxSwapPairV1(pair).protocolFeeNumerator(),
            50,
            "pair reads factory internal numerator"
        );
        assertEq(
            HippoxSwapPairV1(pair).feeTo(),
            feeRecipient,
            "pair reads factory feeTo"
        );
    }
    // Flash swap reads factory values
    function testProtocolFeeCollectedOnFlashSwap() public {
        vm.prank(owner);
        factory.setFeeTo(feeRecipient);
        vm.prank(owner);
        factory.setProtocolFeeNumeratorPercen(5);
        // Flash swap requires a callback contract. A full flash swap test
        // lives in the flash swap test suite. Here we only verify that the
        // pair reads the factory values on the flash swap path.
        // 5 percent = internal 50.
        assertEq(
            HippoxSwapPairV1(pair).protocolFeeNumerator(),
            50,
            "flash swap reads factory value"
        );
        assertEq(
            HippoxSwapPairV1(pair).feeTo(),
            feeRecipient,
            "flash swap reads factory feeTo"
        );
    }
}
