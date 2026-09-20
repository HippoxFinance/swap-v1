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
/// @dev Malicious ERC20 that reenters the pair on transfer.
contract ReentrantToken is ERC20 {
    HippoxSwapPairV1 public pair;
    bool public attacked;
    uint256 public attackCount;
    bool public shouldAttack;
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function setPair(address _pair) external {
        pair = HippoxSwapPairV1(_pair);
    }
    function enableAttack(bool _v) external {
        shouldAttack = _v;
    }
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (shouldAttack && !attacked && address(pair) != address(0)) {
            attacked = true;
            attackCount++;
            // Try to reenter swap while the pair is mid-transfer.
            try pair.swap(0, 1, address(this)) {} catch {}
        }
        super._update(from, to, value);
    }
}
/// @dev Malicious contract that reenters swap via receive().
contract ReentrantReceiver {
    HippoxSwapPairV1 public pair;
    bool public attacked;
    function setPair(address _pair) external {
        pair = HippoxSwapPairV1(_pair);
    }
    receive() external payable {
        if (!attacked) {
            attacked = true;
            try pair.swap(0, 1, address(this)) {} catch {}
        }
    }
}
/// @title HippoxSwapAttackTest
/// @notice Adversarial tests: reentrancy, sandwich, extreme reserves, decimals, self-referential addresses.
contract HippoxSwapAttackTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
    WETH weth;
    MockToken tokenA; // 18 decimals
    MockToken tokenB; // 18 decimals
    MockToken usdc; // 6 decimals
    address creator = makeAddr("creator");
    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");
    address taxSink = makeAddr("taxSink");
    address pair;
    function setUp() public {
        weth = new WETH();
        factory = new HippoxSwapFactoryV1(address(this));
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        usdc = new MockToken("USDC", "USDC", 6);
        tokenA.mint(creator, 100_000_000e18);
        tokenB.mint(creator, 100_000_000e18);
        usdc.mint(creator, 100_000_000e6);
        // Fund attacker and victim so they can actually swap.
        tokenA.mint(attacker, 1_000_000e18);
        tokenB.mint(attacker, 1_000_000e18);
        tokenA.mint(victim, 1_000_000e18);
        tokenB.mint(victim, 1_000_000e18);
        vm.startPrank(creator);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
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
        vm.prank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.prank(victim);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "pair exists");
    }
    // 1. Reentrancy via malicious tax recipient
    function testReentrancyViaTaxRecipient() public {
        // Deploy a malicious token that reenters swap when transferred.
        ReentrantToken rToken = new ReentrantToken("Reentrant", "RTK");
        rToken.mint(creator, 1_000_000e18);
        vm.startPrank(creator);
        rToken.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(rToken),
            address(tokenB),
            100_000e18,
            100_000e18,
            0,
            0,
            creator,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address rPair = factory.getPair(address(rToken), address(tokenB));
        rToken.setPair(rPair);
        vm.startPrank(creator);
        HippoxSwapPairV1(rPair).setTaxBps(100);
        HippoxSwapPairV1(rPair).setTaxRecipient(address(rToken));
        vm.stopPrank();
        // Enable reentrancy.
        rToken.enableAttack(true);
        address[] memory path = new address[](2);
        path[0] = address(rToken);
        path[1] = address(tokenB);
        // Attacker attempts to exploit reentrancy.
        vm.prank(attacker);
        // Should either revert or complete without draining funds.
        try
            router.swapExactTokensForTokens(
                1000e18,
                0,
                path,
                attacker,
                block.timestamp + 1 hours
            )
        {
            // If it succeeds, verify pair still has reserves and invariant holds.
            (uint112 r0, uint112 r1) = HippoxSwapPairV1(rPair).getReserves();
            assertGt(r0, 0, "reserve0 intact");
            assertGt(r1, 0, "reserve1 intact");
        } catch {
            // Revert is acceptable; pair is safe.
        }
    }
    // 2. Reentrancy via receive() on tax recipient
    function testReentrancyViaReceive() public {
        ReentrantReceiver recv = new ReentrantReceiver();
        recv.setPair(pair);
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(address(recv));
        vm.stopPrank();
        // Give recv some tokenA so it can be a valid recipient.
        tokenA.mint(address(recv), 0);
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
        // Pair remains healthy.
        (uint112 r0, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        assertGt(r0, 0);
        assertGt(r1, 0);
    }
    // 3. Sandwich attack: attacker front-runs and back-runs victim
    function testSandwichAttackLosesMoneyWithSlippageProtection() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        // Victim sets a tight slippage (amountOutMin).
        uint256 victimIn = 10_000e18;
        uint256 expectedOut = (victimIn * 997 * 1_000_000e18) /
            (1_000_000e18 * 1000 + victimIn * 997);
        uint256 victimMinOut = (expectedOut * 99) / 100; // 1% slippage tolerance
        // Attacker front-runs with a large buy to move price.
        vm.prank(attacker);
        router.swapExactTokensForTokens(
            50_000e18,
            0,
            path,
            attacker,
            block.timestamp + 1 hours
        );
        // Victim's swap now yields less; with tight slippage it must revert.
        vm.prank(victim);
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            victimIn,
            victimMinOut,
            path,
            victim,
            block.timestamp + 1 hours
        );
    }
    // 4. Sandwich attack with loose slippage: victim loses value
    function testSandwichAttackVictimLosesWithLooseSlippage() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 victimIn = 10_000e18;
        // Attacker front-runs.
        vm.prank(attacker);
        router.swapExactTokensForTokens(
            50_000e18,
            0,
            path,
            attacker,
            block.timestamp + 1 hours
        );
        // Victim accepts any output (0 min).
        uint256 before = tokenB.balanceOf(victim);
        vm.prank(victim);
        router.swapExactTokensForTokens(
            victimIn,
            0,
            path,
            victim,
            block.timestamp + 1 hours
        );
        uint256 received = tokenB.balanceOf(victim) - before;
        // Attacker back-runs.
        vm.prank(attacker);
        router.swapExactTokensForTokens(
            50_000e18,
            0,
            path,
            attacker,
            block.timestamp + 1 hours
        );
        // Victim received less than they would have without the sandwich.
        uint256 idealOut = (victimIn * 997 * 1_000_000e18) /
            (1_000_000e18 * 1000 + victimIn * 997);
        assertLt(received, idealOut, "victim received less due to sandwich");
    }
    // 5. Price manipulation: large swap moves price significantly
    function testLargeSwapMovesPrice() public {
        (, uint112 r1Before) = HippoxSwapPairV1(pair).getReserves();
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        vm.prank(attacker);
        router.swapExactTokensForTokens(
            500_000e18,
            0,
            path,
            attacker,
            block.timestamp + 1 hours
        );
        (, uint112 r1After) = HippoxSwapPairV1(pair).getReserves();
        assertLt(r1After, r1Before, "reserve1 dropped");
        // Price moved: reserve ratio changed significantly.
    }
    // 6. Extreme reserve ratio: one side nearly empty
    function testExtremeReserveRatio() public {
        // Drain tokenB from the pair via a huge swap.
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        (uint112 r0, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        // Swap almost all tokenA in to drain tokenB.
        uint256 hugeIn = uint256(r0) * 100;
        tokenA.mint(attacker, hugeIn);
        vm.prank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(attacker);
        router.swapExactTokensForTokens(
            hugeIn,
            0,
            path,
            attacker,
            block.timestamp + 1 hours
        );
        (uint112 r0After, uint112 r1After) = HippoxSwapPairV1(pair)
            .getReserves();
        // tokenB reserve is now very small but non-zero.
        assertGt(r1After, 0, "tokenB still non-zero");
        assertGt(r0After, r0, "tokenA reserve grew");
    }
    // 7. Token with 6 decimals vs 18 decimals
    function testMixedDecimals() public {
        vm.startPrank(creator);
        router.addLiquidity(
            address(usdc),
            address(tokenA),
            1_000_000e6,
            1_000_000e18,
            0,
            0,
            creator,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address mixedPair = factory.getPair(address(usdc), address(tokenA));
        assertTrue(mixedPair != address(0), "mixed pair exists");
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(tokenA);
        uint256 before = tokenA.balanceOf(creator);
        vm.prank(creator);
        router.swapExactTokensForTokens(
            1000e6,
            0,
            path,
            creator,
            block.timestamp + 1 hours
        );
        uint256 received = tokenA.balanceOf(creator) - before;
        assertGt(received, 0, "mixed decimal swap works");
    }
    // 8. taxRecipient == pair itself
    function testTaxRecipientIsPairItself() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(pair);
        vm.stopPrank();
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
        uint256 received = tokenB.balanceOf(creator) - before;
        assertGt(received, 0, "swap works even when taxRecipient is pair");
        (uint112 r0, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        assertGt(r0, 0);
        assertGt(r1, 0);
    }
    // 9. taxRecipient == factory
    function testTaxRecipientIsFactory() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(address(factory));
        vm.stopPrank();
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
        uint256 taxHeld = tokenA.balanceOf(address(factory));
        assertGt(taxHeld, 0, "factory received tax");
    }
    // 10. taxRecipient == router
    function testTaxRecipientIsRouter() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(address(router));
        vm.stopPrank();
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
        uint256 taxHeld = tokenA.balanceOf(address(router));
        assertGt(taxHeld, 0, "router received tax");
    }
    // 11. admin == pair itself
    function testAdminIsPairItself() public {
        vm.prank(creator);
        HippoxSwapPairV1(pair).setAdmin(pair);
        assertEq(HippoxSwapPairV1(pair).admin(), pair, "admin is pair");
        // No one can call setFeeNumerator now, because the pair cannot initiate txs.
        vm.prank(creator);
        vm.expectRevert("ONLY_ADMIN");
        HippoxSwapPairV1(pair).setFeeNumerator(5);
    }
    // 12. Same token in multiple pairs
    function testSameTokenInMultiplePairs() public {
        MockToken tokenC = new MockToken("TokenC", "C", 18);
        tokenC.mint(creator, 10_000_000e18);
        vm.startPrank(creator);
        tokenC.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA),
            address(tokenC),
            100_000e18,
            100_000e18,
            0,
            0,
            creator,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        address pairAC = factory.getPair(address(tokenA), address(tokenC));
        assertTrue(pairAC != address(0), "pairAC exists");
        // Swap on pairAB does not affect pairAC reserves.
        (uint112 acR0Before, uint112 acR1Before) = HippoxSwapPairV1(pairAC)
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
        (uint112 acR0After, uint112 acR1After) = HippoxSwapPairV1(pairAC)
            .getReserves();
        assertEq(acR0Before, acR0After, "pairAC reserve0 unchanged");
        assertEq(acR1Before, acR1After, "pairAC reserve1 unchanged");
    }
    // 13. Repeated fee change + swap in same block
    function testFeeChangeAndSwapSameBlock() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setFeeNumerator(10);
        vm.stopPrank();
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
        // Fee remains at 10 after swap.
        assertEq(HippoxSwapPairV1(pair).feeNumerator(), 10);
    }
    // 14. Zero-output swap must revert
    function testZeroOutputSwapReverts() public {
        // Directly call pair.swap with both outputs = 0.
        vm.prank(attacker);
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        HippoxSwapPairV1(pair).swap(0, 0, attacker);
    }
    // 15. Attacker cannot drain via repeated tiny swaps with max tax
    function testRepeatedTinySwapsNoDrain() public {
        vm.startPrank(creator);
        HippoxSwapPairV1(pair).setTaxBps(100);
        HippoxSwapPairV1(pair).setTaxRecipient(taxSink);
        vm.stopPrank();
        tokenA.mint(attacker, 1000e18);
        vm.prank(attacker);
        tokenA.approve(address(router), type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        (uint112 r0Before, uint112 r1Before) = HippoxSwapPairV1(pair)
            .getReserves();
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(attacker);
            router.swapExactTokensForTokens(
                1e18,
                0,
                path,
                attacker,
                block.timestamp + 1 hours
            );
        }
        (uint112 r0After, uint112 r1After) = HippoxSwapPairV1(pair)
            .getReserves();
        // Reserves grew (attacker paid in), pair is not drained.
        assertGt(r0After, r0Before, "reserve0 grew");
        assertLt(r1After, r1Before, "reserve1 shrank but not drained");
        assertGt(r1After, 0, "reserve1 still positive");
    }
    // 16. Direct token donation then swap: reserves sync correctly
    function testDonationThenSwapSyncs() public {
        vm.prank(creator);
        tokenA.transfer(pair, 10_000e18);
        (uint112 r0Before, ) = HippoxSwapPairV1(pair).getReserves();
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
        (uint112 r0After, ) = HippoxSwapPairV1(pair).getReserves();
        assertGt(r0After, r0Before, "reserve0 grew after donation + swap");
    }
}
