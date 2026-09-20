// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxSwapPairV1} from "../src/HippoxSwapPairV1.sol";
import {WETH} from "../src/WETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract MockToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
/// @dev Token that reverts on transfer to a specific address, used to test tax recipient failures.
contract RejectingToken is ERC20 {
    address public rejectRecipient;
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function setRejectRecipient(address _r) external {
        rejectRecipient = _r;
    }
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (to == rejectRecipient && rejectRecipient != address(0)) {
            revert("RECIPIENT_REJECTS");
        }
        super._update(from, to, value);
    }
}
/// @title HippoxSwapTaxTest
/// @notice Aggressive tests for adjustable AMM fee, trading tax, admin role switching, and edge cases.
contract HippoxSwapTaxTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    address creator = makeAddr("creator");
    address newAdmin = makeAddr("newAdmin");
    address attacker = makeAddr("attacker");
    address taxSink = makeAddr("taxSink");
    address pair;
    function setUp() public {
        weth = new WETH();
        factory = new HippoxSwapFactoryV1(address(this));
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A");
        tokenB = new MockToken("TokenB", "B");
        // Fund creator and attacker.
        tokenA.mint(creator, 10_000_000e18);
        tokenB.mint(creator, 10_000_000e18);
        tokenA.mint(attacker, 10_000_000e18);
        vm.startPrank(creator);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        // Create pair and seed liquidity.
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            creator,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        // Attacker also needs allowance to swap.
        vm.prank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair must exist");
    }
    // Defaults
    function testDefaultFeeAndTax() public view {
        assertEq(
            HippoxSwapPairV1(pair).feeNumerator(),
            3,
            "default AMM fee = 0.3%"
        );
        assertEq(HippoxSwapPairV1(pair).taxBps(), 10, "default tax = 0.1%");
        assertEq(HippoxSwapPairV1(pair).creator(), creator, "creator set");
        assertEq(
            HippoxSwapPairV1(pair).admin(),
            creator,
            "admin defaults to creator"
        );
    }
    // Admin switching
    function testCreatorCanSwitchAdmin() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setAdmin(newAdmin);
        assertEq(HippoxSwapPairV1(pair).admin(), newAdmin, "admin switched");
        // Old admin (creator) can no longer set fee.
        vm.prank(creator);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setFeeNumerator(5);
        // New admin can.
        vm.prank(newAdmin);
        HippoxSwapPairV1(pair).setFeeNumerator(5);
        assertEq(HippoxSwapPairV1(pair).feeNumerator(), 5);
    }
    function testOnlyCreatorCanSwitchAdmin() public {
        vm.prank(attacker);
        vm.expectRevert("ONLY_CREATOR");
        HippoxSwapPairV1(pair).setAdmin(attacker);
        vm.prank(newAdmin);
        vm.expectRevert("ONLY_CREATOR");
        HippoxSwapPairV1(pair).setAdmin(attacker);
    }
    function testCannotSetAdminToZero() public {
        vm.prank(creator);
        vm.expectRevert("ZERO_ADDRESS");
        HippoxSwapPairV1(pair).setAdmin(address(0));
    }
    function testNewAdminCannotSwitchAdmin() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setAdmin(newAdmin);
        // Even the new admin cannot switch admin; only creator can.
        vm.prank(newAdmin);
        vm.expectRevert("ONLY_CREATOR");
        HippoxSwapPairV1(pair).setAdmin(attacker);
    }
    // Fee bounds
    function testSetFeeToMax() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(10); // 1%
        assertEq(HippoxSwapPairV1(pair).feeNumerator(), 10);
    }
    function testSetFeeOverMaxReverts() public {
        vm.prank(creator);
        vm.expectRevert("FEE_TOO_HIGH");
        HippoxSwapPairV1(pair).setFeeNumerator(11);
    }
    function testSetFeeToZero() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(0);
        assertEq(HippoxSwapPairV1(pair).feeNumerator(), 0);
    }
    function testNonAdminCannotSetFee() public {
        vm.prank(attacker);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setFeeNumerator(5);
    }
    // Tax bounds
    function testSetTaxToMax() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100); // 1%
        assertEq(HippoxSwapPairV1(pair).taxBps(), 100);
    }
    function testSetTaxOverMaxReverts() public {
        vm.prank(creator);
        vm.expectRevert("TAX_TOO_HIGH");
        HippoxSwapPairV1(pair).setTaxBps(101);
    }
    function testNonAdminCannotSetTax() public {
        vm.prank(attacker);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setTaxBps(50);
    }
    // Tax recipient
    function testSetTaxRecipient() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        assertEq(HippoxSwapPairV1(pair).taxRecipient(), taxSink);
    }
    function testCannotSetTaxRecipientToZero() public {
        vm.prank(creator);
        vm.expectRevert("ZERO_ADDRESS");
        HippoxSwapPairV1(pair).setTaxRecipient(address(0));
    }
    function testNonAdminCannotSetTaxRecipient() public {
        vm.prank(attacker);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setTaxRecipient(attacker);
    }
    // Extreme: max fee + max tax, then verify output is heavily reduced
    function testMaxFeeAndMaxTaxReduceOutput() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 amountIn = 1000e18;
        uint256 beforeB = tokenB.balanceOf(creator);
        uint256 beforeTax = tokenA.balanceOf(taxSink);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(creator) - beforeB;
        uint256 taxPaid = tokenA.balanceOf(taxSink) - beforeTax;
        assertEq(taxPaid, 10e18, "tax collected at 1%");
        assertLt(received, 990e18, "output reduced by fee + tax");
        assertGt(received, 0, "output must be positive");
    }
    // Extreme: zero fee + zero tax -> maximum output
    function testZeroFeeZeroTaxGivesMaxOutput() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(0);
        HippoxSwapPairV1(pair).setTaxBps(0);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 amountIn = 1000e18;
        uint256 beforeB = tokenB.balanceOf(creator);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(creator) - beforeB;
        assertGt(
            received,
            990e18,
            "zero-fee output should be near constant product"
        );
    }
    // Extreme: repeated fee changes in a single test
    function testRapidFeeChanges() public {
        for (uint256 i = 0; i <= 10; i++) {
            vm.prank(creator);
            HippoxSwapPairV1(pair).setFeeNumerator(i);
            assertEq(HippoxSwapPairV1(pair).feeNumerator(), i);
        }
        vm.prank(creator);
        vm.expectRevert("FEE_TOO_HIGH");
        HippoxSwapPairV1(pair).setFeeNumerator(11);
    }
    function testRapidTaxChanges() public {
        for (uint256 i = 0; i <= 100; i += 10) {
            vm.prank(creator);
            HippoxSwapPairV1(pair).setTaxBps(i);
            assertEq(HippoxSwapPairV1(pair).taxBps(), i);
        }
        vm.prank(creator);
        vm.expectRevert("TAX_TOO_HIGH");
        HippoxSwapPairV1(pair).setTaxBps(101);
    }
    // Attack: attacker tries every privileged call
    function testAttackerCannotDoAnything() public {
        vm.startPrank(attacker);
        vm.expectRevert("ONLY_CREATOR");
        HippoxSwapPairV1(pair).setAdmin(attacker);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setTaxBps(100);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setTaxRecipient(attacker);
        vm.stopPrank();
    }
    // Admin transfer then old admin locked out entirely
    function testAdminTransferLocksOutOldAdmin() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setAdmin(newAdmin);
        vm.startPrank(creator);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setFeeNumerator(5);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setTaxBps(50);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setTaxRecipient(creator);
        vm.stopPrank();
        // New admin works.
        vm.startPrank(newAdmin);
        HippoxSwapPairV1(pair).setFeeNumerator(5);
        HippoxSwapPairV1(pair).setTaxBps(50);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        assertEq(HippoxSwapPairV1(pair).feeNumerator(), 5);
        assertEq(HippoxSwapPairV1(pair).taxBps(), 50);
        assertEq(HippoxSwapPairV1(pair).taxRecipient(), taxSink);
    }
    // Tax goes to recipient, not to LP
    function testTaxGoesToRecipientNotPool() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100); // 1%
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeTax = tokenA.balanceOf(taxSink);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 taxPaid = tokenA.balanceOf(taxSink) - beforeTax;
        assertEq(taxPaid, 10e18, "tax goes to recipient");
    }
    // Fee stays in pool (LP benefit)
    function testFeeStaysInPool() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxBps(0);
        // Disable protocol fee so the full input stays in the pool.
        // The factory owner must set protocolFeeNumeratorPercen to 0.
        // For this test we assume the factory is owned by address(this).
        HippoxSwapFactoryV1(factory).setProtocolFeeNumeratorPercen(0);
        (uint112 r0Before, uint112 r1Before) = HippoxSwapPairV1(pair)
            .getReserves();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        (uint112 r0After, uint112 r1After) = HippoxSwapPairV1(pair)
            .getReserves();
        assertEq(
            uint256(r0After) - uint256(r0Before),
            1000e18,
            "full input added"
        );
        assertLt(r1After, r1Before, "tokenB reserve decreased");
    }
    // 1. Fee change immediately affects swap output
    function testFeeChangeImmediatelyAffectsOutput() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Zero fee, zero tax -> max output.
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(0);
        HippoxSwapPairV1(pair).setTaxBps(0);
        vm.stopPrank();
        uint256 before1 = tokenB.balanceOf(creator);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 outZeroFee = tokenB.balanceOf(creator) - before1;
        // Max fee (1%) + max tax (1%) -> strictly less output.
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        uint256 before2 = tokenB.balanceOf(creator);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 outMaxFee = tokenB.balanceOf(creator) - before2;
        assertGt(outZeroFee, outMaxFee, "higher fee+tax must reduce output");
    }
    // 2. Tax recipient rejects tokens -> swap must revert safely
    function testTaxRecipientRejectingTokenRevertsSafely() public {
        RejectingToken rt = new RejectingToken("Reject", "RJT");
        rt.mint(creator, 1_000_000e18);
        vm.startPrank(creator);
        rt.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(rt),
            address(tokenB),
            100_000e18,
            100_000e18,
            0,
            0,
            creator,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address rtPair = factory.getPair(address(rt), address(tokenB));
        assertTrue(rtPair != address(0), "rt pair exists");
        // Set tax recipient to an address the token rejects.
        rt.setRejectRecipient(taxSink);
        vm.startPrank(creator);
        HippoxSwapPairV1(rtPair).setTaxBps(100); // 1%
        HippoxSwapPairV1(rtPair).setTaxRecipient(taxSink);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(rt);
        path[1] = address(tokenB);
        // Swap must revert because tax transfer to taxSink fails.
        vm.prank(creator);
        vm.expectRevert();
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
    }
    // 3. Zero tax -> swap works regardless of recipient
    function testZeroTaxWithZeroRecipientSkipsTax() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxBps(0);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 before = tokenB.balanceOf(creator);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        assertGt(
            tokenB.balanceOf(creator) - before,
            0,
            "swap works with zero tax"
        );
    }
    // 4. Tiny amount tax proportionality
    function testTinyAmountTaxProportional() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(10); // 0.1%
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 tinyInput = 1e6; // 0.000001 token
        uint256 beforeTax = tokenA.balanceOf(taxSink);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            tinyInput,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 taxTaken = tokenA.balanceOf(taxSink) - beforeTax;
        // tax = 1e6 * 10 / 10000 = 1000 wei
        assertEq(taxTaken, 1000, "tiny input tax proportional");
    }
    function testMinimumViableSwap() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxBps(0);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            10_000,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
    }
    // 5. Large amount near reserve boundary
    function testLargeAmountNearReserve() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxBps(0);
        (uint112 r0, ) = HippoxSwapPairV1(pair).getReserves();
        uint256 hugeAmount = uint256(r0) / 2;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        tokenA.mint(creator, hugeAmount);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            hugeAmount,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
    }
    function testSwapWithOutputEqualToReserveReverts() public {
        (, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        vm.prank(creator);
        vm.expectRevert("INSUFFICIENT_LIQUIDITY");
        HippoxSwapPairV1(pair).swap(0, r1, creator);
    }
    // 6. Repeated swaps in a single test
    function testManyConsecutiveSwaps() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setTaxBps(0);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(creator);
            router.swapExactTokensForTokens(
                100e18,
                0,
                path,
                creator,
                block.timestamp + 1 hours
            );
        }
        (uint112 r0, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        assertGt(r0, 0, "reserve0 non-zero");
        assertGt(r1, 0, "reserve1 non-zero");
    }
    // 7. Admin switch then immediate fee change and swap
    function testNewAdminChangesFeeThenSwap() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setAdmin(newAdmin);
        vm.startPrank(newAdmin);
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeTax = tokenA.balanceOf(taxSink);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 taxTaken = tokenA.balanceOf(taxSink) - beforeTax;
        assertEq(taxTaken, 10e18, "1% of 1000e18");
    }
    // 8. createPair argument validation
    function testCreatePairZeroCreatorReverts() public {
        MockToken tokenC = new MockToken("TokenC", "C");
        MockToken tokenD = new MockToken("TokenD", "D");
        vm.expectRevert("ZERO_CREATOR");
        factory.createPair(address(tokenC), address(tokenD), address(0));
    }
    function testCreatePairZeroTokenReverts() public {
        MockToken tokenC = new MockToken("TokenC", "C");
        vm.expectRevert("ZERO_ADDRESS");
        factory.createPair(address(0), address(tokenC), creator);
    }
    function testCreatePairIdenticalTokensReverts() public {
        vm.expectRevert("IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA), creator);
    }
    function testCreatePairDuplicateReverts() public {
        // Pair already exists from setUp.
        vm.expectRevert("PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB), creator);
    }
    // 9. allPairs not polluted by failed createPair
    function testCreatePairRevertDoesNotPolluteAllPairs() public {
        uint256 before = factory.allPairsLength();
        MockToken tokenC = new MockToken("TokenC", "C");
        vm.expectRevert("ZERO_CREATOR");
        factory.createPair(address(tokenC), address(tokenB), address(0));
        assertEq(
            factory.allPairsLength(),
            before,
            "allPairs unchanged after revert"
        );
    }
    // 10. Fee at max then attempt to exceed
    function testFeeAtMaxThenExceedReverts() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        vm.expectRevert("FEE_TOO_HIGH");
        HippoxSwapPairV1(pair).setFeeNumerator(11);
        vm.stopPrank();
        assertEq(HippoxSwapPairV1(pair).feeNumerator(), 10, "fee stays at max");
    }
    // 11. Tax at max then attempt to exceed
    function testTaxAtMaxThenExceedReverts() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        vm.expectRevert("TAX_TOO_HIGH");
        HippoxSwapPairV1(pair).setTaxBps(101);
        vm.stopPrank();
        assertEq(HippoxSwapPairV1(pair).taxBps(), 100, "tax stays at max");
    }
    // 12. Attacker cannot drain tax by swapping tiny amounts repeatedly
    function testAttackerCannotDrainTaxViaTinySwaps() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeSink = tokenA.balanceOf(taxSink);
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(attacker);
            router.swapExactTokensForTokens(
                1e18,
                0,
                path,
                attacker,
                block.timestamp + 1 hours
            );
        }
        uint256 sinkGain = tokenA.balanceOf(taxSink) - beforeSink;
        // Tax should be roughly 10 * 1% of 1e18 = 0.1e18.
        assertGt(sinkGain, 0, "tax accumulated");
        assertLt(sinkGain, 0.2e18, "tax is proportional, not exploitable");
    }
    // 13. Creator cannot bypass admin check to set fee
    function testCreatorCannotSetFeeAfterTransfer() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setAdmin(newAdmin);
        vm.prank(creator);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setFeeNumerator(10);
    }
    // 14. Swap with stale reserves after direct token donation
    function testDirectDonationDoesNotBreakInvariant() public {
        // Donate tokens directly to the pair; reserves are not synced.
        vm.prank(creator);
        tokenA.transfer(pair, 1000e18);
        // A swap should still work and sync reserves correctly.
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            100e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        (uint112 r0, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        assertGt(r0, 0);
        assertGt(r1, 0);
    }
    // 15. Multi-hop swap with tax and fee at max
    function testMultiHopWithMaxFeeAndTax() public {
        MockToken tokenC = new MockToken("TokenC", "C");
        tokenC.mint(creator, 1_000_000e18);
        vm.startPrank(creator);
        tokenC.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            100_000e18,
            100_000e18,
            0,
            0,
            creator,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address pairBC = factory.getPair(address(tokenB), address(tokenC));
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pairBC).setFeeNumerator(10);
        HippoxSwapPairV1(pairBC).setTaxBps(100);
        vm.stopPrank();
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        uint256 beforeC = tokenC.balanceOf(creator);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 received = tokenC.balanceOf(creator) - beforeC;
        assertGt(received, 0, "multi-hop with max fees still yields output");
        assertLt(received, 990e18, "fees reduce output across hops");
    }
}
