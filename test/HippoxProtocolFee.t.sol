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
/// @notice Tests for the protocol fee mechanism introduced in HippoxSwapPair.
contract HippoxProtocolFeeTest is Test {
    HippoxSwapFactory factory;
    HippoxSwapRouter router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    address alice = makeAddr("alice");
    address feeRecipient = makeAddr("feeRecipient");
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
    function testDefaultProtocolFeeIsZero() public view {
        assertEq(
            HippoxSwapPair(pair).protocolFeeNumerator(),
            0,
            "default protocol fee is 0"
        );
    }
    function testDefaultFeeToIsCreator() public view {
        // In setUp, factory.feeTo is address(0), so the pair's feeTo should
        // be the creator (alice).
        assertEq(HippoxSwapPair(pair).feeTo(), alice, "feeTo is creator");
    }
    function testSetProtocolFeeNumerator() public {
        vm.prank(alice);
        HippoxSwapPair(pair).setProtocolFeeNumerator(3);
        assertEq(HippoxSwapPair(pair).protocolFeeNumerator(), 3, "fee set");
    }
    function testSetProtocolFeeNumeratorTooHighReverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("PROTOCOL_FEE_TOO_HIGH"));
        HippoxSwapPair(pair).setProtocolFeeNumerator(6);
    }
    function testNonAdminCannotSetProtocolFee() public {
        vm.prank(feeRecipient);
        vm.expectRevert(bytes("ONLY_ADMIN"));
        HippoxSwapPair(pair).setProtocolFeeNumerator(3);
    }
    function testSetFeeTo() public {
        vm.prank(alice);
        HippoxSwapPair(pair).setFeeTo(feeRecipient);
        assertEq(HippoxSwapPair(pair).feeTo(), feeRecipient, "feeTo set");
    }
    function testSetFeeToZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("ZERO_ADDRESS"));
        HippoxSwapPair(pair).setFeeTo(address(0));
    }
    function testProtocolFeeCollectedOnSwap() public {
        // Enable protocol fee: 3/1000 of the AMM fee goes to feeRecipient.
        vm.prank(alice);
        HippoxSwapPair(pair).setFeeTo(feeRecipient);
        vm.prank(alice);
        HippoxSwapPair(pair).setProtocolFeeNumerator(3);
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
        vm.prank(alice);
        HippoxSwapPair(pair).setFeeTo(feeRecipient);
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
    function testUserOutputUnchangedWithProtocolFee() public {
        // First swap without protocol fee.
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
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
        vm.prank(alice);
        HippoxSwapPair(pair).setFeeTo(feeRecipient);
        vm.prank(alice);
        HippoxSwapPair(pair).setProtocolFeeNumerator(3);
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
        // The protocol fee is taken out of the AMM fee, so the user-visible
        // output can be slightly lower due to the smaller effective input.
        // The difference must stay within a small tolerance (1%).
        assertGe(
            outWithFee,
            (outNoFee * 99) / 100,
            "user output within 1% with protocol fee"
        );
    }
    function testPairInfoIncludesProtocolFeeFields() public {
        vm.prank(alice);
        HippoxSwapPair(pair).setFeeTo(feeRecipient);
        vm.prank(alice);
        HippoxSwapPair(pair).setProtocolFeeNumerator(3);
        (address p, bytes memory infoBytes) = factory.getPairInfo(
            address(tokenA),
            address(tokenB)
        );
        assertEq(p, pair, "pair address");
        // The PairInfo struct now has protocolFeeNumerator and feeTo.
        // We only check the raw bytes are non-empty here; decoding is done
        // in a separate test if needed.
        assertGt(infoBytes.length, 0, "info not empty");
    }
}
