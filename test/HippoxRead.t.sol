// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
import {HippoxSwapFactory} from "../src/HippoxSwapFactory.sol";
import {HippoxSwapRouter} from "../src/HippoxSwapRouter.sol";
import {HippoxSwapPair} from "../src/HippoxSwapPair.sol";
import {WETH} from "../src/WETH.sol";
import {IHippoxSwapPair} from "../src/interfaces/IHippoxSwapPair.sol";
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
/// @title HippoxReadTest
/// @notice Prints and validates the extended read functions.
contract HippoxReadTest is Test {
    HippoxSwapFactory factory;
    HippoxSwapRouter router;
    WETH weth;
    MockToken tokenA;
    MockToken tokenB;
    MockToken tokenC;
    address alice = makeAddr("alice");
    address pairAB;
    address pairBC;
    function setUp() public {
        weth = new WETH();
        factory = new HippoxSwapFactory(address(this));
        router = new HippoxSwapRouter(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
        tokenC = new MockToken("TokenC", "C", 18);
        tokenA.mint(alice, 10_000_000e18);
        tokenB.mint(alice, 10_000_000e18);
        tokenC.mint(alice, 10_000_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
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
        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            alice,
            block.timestamp + 1 hours
        );
        vm.stopPrank();
        pairAB = factory.getPair(address(tokenA), address(tokenB));
        pairBC = factory.getPair(address(tokenB), address(tokenC));
    }
    // getPairInfo
    function testPrintPairInfo() public view {
        IHippoxSwapPair.PairInfo memory info = HippoxSwapPair(pairAB)
            .getPairInfo();
        console.log("=== PairInfo for pairAB ===");
        console.log("token0:", info.token0);
        console.log("token1:", info.token1);
        console.log("reserve0:", info.reserve0);
        console.log("reserve1:", info.reserve1);
        console.log("feeNumerator:", info.feeNumerator);
        console.log("feeDenominator:", info.feeDenominator);
        console.log("maxFeeNumerator:", info.maxFeeNumerator);
        console.log("taxBps:", info.taxBps);
        console.log("maxTaxBps:", info.maxTaxBps);
        console.log("bpsDenominator:", info.bpsDenominator);
        console.log("taxRecipient:", info.taxRecipient);
        console.log("totalSupply:", info.totalSupply);
        console.log("creator:", info.creator);
        console.log("admin:", info.admin);
        console.log("minimumLiquidity:", info.minimumLiquidity);
        assertEq(info.token0, address(tokenA));
        assertEq(info.token1, address(tokenB));
        assertGt(info.reserve0, 0);
        assertGt(info.reserve1, 0);
        assertEq(info.feeNumerator, 3);
        assertEq(info.taxBps, 10);
    }
    // Pair.getAmountOut (tax-inclusive)
    function testPrintPairGetAmountOut() public view {
        uint256 amountIn = 1000e18;
        uint256 out = HippoxSwapPair(pairAB).getAmountOut(
            amountIn,
            address(tokenA)
        );
        console.log("=== Pair.getAmountOut ===");
        console.log("amountIn (tokenA):", amountIn);
        console.log("amountOut (tokenB, net):", out);
        assertGt(out, 0);
        assertLt(out, amountIn);
    }
    function testPairQuoteMatchesSwap() public {
        uint256 amountIn = 1000e18;
        uint256 quoted = HippoxSwapPair(pairAB).getAmountOut(
            amountIn,
            address(tokenA)
        );
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 beforeBal = tokenB.balanceOf(alice);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 actual = tokenB.balanceOf(alice) - beforeBal;
        vm.stopPrank();
        console.log("quoted:", quoted);
        console.log("actual:", actual);
        assertEq(quoted, actual, "quote must equal actual swap output");
    }
    // Router.quote (multi-hop, tax-inclusive)
    function testPrintRouterQuote() public view {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        uint256[] memory amounts = router.quote(1000e18, path);
        console.log("=== Router.quote (A -> B -> C) ===");
        console.log("amounts[0] (A in):", amounts[0]);
        console.log("amounts[1] (B mid):", amounts[1]);
        console.log("amounts[2] (C out):", amounts[2]);
        assertEq(amounts[0], 1000e18);
        assertGt(amounts[1], 0);
        assertGt(amounts[2], 0);
        assertLt(amounts[2], amounts[1]);
    }
    function testRouterQuoteMatchesSwap() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        uint256[] memory quoted = router.quote(1000e18, path);
        vm.startPrank(alice);
        uint256 beforeBal = tokenC.balanceOf(alice);
        router.swapExactTokensForTokens(
            1000e18,
            0,
            path,
            alice,
            block.timestamp + 1 hours
        );
        uint256 actual = tokenC.balanceOf(alice) - beforeBal;
        vm.stopPrank();
        console.log("quoted C:", quoted[2]);
        console.log("actual C:", actual);
        assertEq(
            quoted[2],
            actual,
            "router quote must equal actual multi-hop output"
        );
    }
    // Router.quoteBatch
    function testPrintRouterQuoteBatch() public view {
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 1000e18;
        amountsIn[1] = 2000e18;
        address[][] memory paths = new address[][](2);
        paths[0] = new address[](2);
        paths[0][0] = address(tokenA);
        paths[0][1] = address(tokenB);
        paths[1] = new address[](3);
        paths[1][0] = address(tokenA);
        paths[1][1] = address(tokenB);
        paths[1][2] = address(tokenC);
        uint256[][] memory results = router.quoteBatch(amountsIn, paths);
        console.log("=== Router.quoteBatch ===");
        console.log("path0 in:", amountsIn[0]);
        console.log("path0 out:", results[0][results[0].length - 1]);
        console.log("path1 in:", amountsIn[1]);
        console.log("path1 out:", results[1][results[1].length - 1]);
        assertGt(results[0][1], 0);
        assertGt(results[1][2], 0);
    }
    // Factory.getPairsPaginated
    function testPrintFactoryPaginated() public view {
        uint256 total = factory.allPairsLength();
        console.log("=== Factory.getPairsPaginated ===");
        console.log("total pairs:", total);
        address[] memory page0 = factory.getPairsPaginated(0, 10);
        console.log("page0 length:", page0.length);
        assertEq(page0.length, total);
        address[] memory empty = factory.getPairsPaginated(total, 10);
        assertEq(empty.length, 0);
        address[] memory rest = factory.getPairsPaginated(1, 10);
        assertEq(rest.length, total - 1);
    }
    // Factory.getPairInfo
    function testPrintFactoryGetPairInfo() public view {
        (address pair, bytes memory infoBytes) = factory.getPairInfo(
            address(tokenA),
            address(tokenB)
        );
        console.log("=== Factory.getPairInfo ===");
        console.log("pair:", pair);
        console.log("info length (bytes):", infoBytes.length);
        assertEq(pair, pairAB);
        assertGt(infoBytes.length, 0);
        IHippoxSwapPair.PairInfo memory info = abi.decode(
            infoBytes,
            (IHippoxSwapPair.PairInfo)
        );
        assertEq(info.token0, address(tokenA));
        assertEq(info.token1, address(tokenB));
    }
    function testFactoryGetPairInfoMissingPair() public {
        MockToken tokenD = new MockToken("TokenD", "D", 18);
        MockToken tokenE = new MockToken("TokenE", "E", 18);
        (address pair, bytes memory infoBytes) = factory.getPairInfo(
            address(tokenD),
            address(tokenE)
        );
        assertEq(pair, address(0));
        assertEq(infoBytes.length, 0);
    }
    // Consistency: Pair.getAmountOut == Library.getAmountsOut single hop
    function testPairQuoteConsistentWithRouterSingleHop() public view {
        uint256 amountIn = 500e18;
        uint256 pairQuote = HippoxSwapPair(pairAB).getAmountOut(
            amountIn,
            address(tokenA)
        );
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory routerQuote = router.quote(amountIn, path);
        console.log("pair quote:", pairQuote);
        console.log("router quote:", routerQuote[1]);
        assertEq(
            pairQuote,
            routerQuote[1],
            "pair and router quotes must match"
        );
    }
    // Quote changes when fee or tax changes
    function testQuoteRespondsToFeeAndTaxChanges() public {
        uint256 amountIn = 1000e18;
        uint256 baseQuote = HippoxSwapPair(pairAB).getAmountOut(
            amountIn,
            address(tokenA)
        );
        console.log("base quote (fee=3, tax=10):", baseQuote);
        vm.prank(alice);
        HippoxSwapPair(pairAB).setFeeNumerator(10); // 1%
        uint256 higherFeeQuote = HippoxSwapPair(pairAB).getAmountOut(
            amountIn,
            address(tokenA)
        );
        console.log("higher fee quote (fee=10):", higherFeeQuote);
        assertLt(higherFeeQuote, baseQuote, "higher fee must reduce quote");
        vm.prank(alice);
        HippoxSwapPair(pairAB).setFeeNumerator(3);
        vm.prank(alice);
        HippoxSwapPair(pairAB).setTaxBps(100); // 1%
        uint256 higherTaxQuote = HippoxSwapPair(pairAB).getAmountOut(
            amountIn,
            address(tokenA)
        );
        console.log("higher tax quote (tax=100):", higherTaxQuote);
        assertLt(higherTaxQuote, baseQuote, "higher tax must reduce quote");
    }
}
