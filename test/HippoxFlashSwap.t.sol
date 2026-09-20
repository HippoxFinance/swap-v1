// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxSwapPairV1} from "../src/HippoxSwapPairV1.sol";
import {WETH} from "../src/WETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
interface IHippoxFlashSwapCallback {
    function flashSwapCallback(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 amount0In,
        uint256 amount1In,
        bytes calldata data
    ) external;
}
/// @dev Test receiver that repays the flash swap by transferring tokens directly.
contract GoodFlashReceiver is IHippoxFlashSwapCallback {
    address public pair;
    address public token0;
    address public token1;
    uint256 public lastAmount0In;
    uint256 public lastAmount1In;
    constructor(address _pair, address _token0, address _token1) {
        pair = _pair;
        token0 = _token0;
        token1 = _token1;
    }
    function flashSwapCallback(
        address,
        uint256,
        uint256,
        uint256 amount0In,
        uint256 amount1In,
        bytes calldata
    ) external override {
        lastAmount0In = amount0In;
        lastAmount1In = amount1In;
        if (amount0In > 0) {
            IERC20(token0).transfer(pair, amount0In);
        }
        if (amount1In > 0) {
            IERC20(token1).transfer(pair, amount1In);
        }
    }
}
/// @dev Test receiver that does NOT repay. The flash swap must revert.
contract BadFlashReceiver is IHippoxFlashSwapCallback {
    function flashSwapCallback(
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external pure override {
        // Intentionally do nothing.
    }
}
contract HippoxFlashSwapTest is Test {
    HippoxSwapFactoryV1 factory;
    HippoxSwapRouterV1 router;
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
    }
    function testFlashSwapGoodRepayment() public {
        GoodFlashReceiver receiver = new GoodFlashReceiver(
            pair,
            address(tokenA),
            address(tokenB)
        );
        tokenA.mint(address(receiver), 10_000e18);
        tokenB.mint(address(receiver), 10_000e18);
        vm.prank(alice);
        HippoxSwapPairV1(pair).flashSwap(100e18, 0, address(receiver), "");
        assertGt(receiver.lastAmount0In(), 0, "amount0In recorded");
        (uint112 r0, uint112 r1) = HippoxSwapPairV1(pair).getReserves();
        assertGt(r0, 0, "reserve0 positive");
        assertGt(r1, 0, "reserve1 positive");
    }
    function testFlashSwapBadRepaymentReverts() public {
        BadFlashReceiver receiver = new BadFlashReceiver();
        vm.prank(alice);
        vm.expectRevert(bytes("INSUFFICIENT_INPUT_AMOUNT"));
        HippoxSwapPairV1(pair).flashSwap(100e18, 0, address(receiver), "");
    }
    function testFlashSwapZeroOutputReverts() public {
        GoodFlashReceiver receiver = new GoodFlashReceiver(
            pair,
            address(tokenA),
            address(tokenB)
        );
        vm.prank(alice);
        vm.expectRevert(bytes("INSUFFICIENT_OUTPUT_AMOUNT"));
        HippoxSwapPairV1(pair).flashSwap(0, 0, address(receiver), "");
    }
    function testFlashSwapTooMuchOutputReverts() public {
        GoodFlashReceiver receiver = new GoodFlashReceiver(
            pair,
            address(tokenA),
            address(tokenB)
        );
        (uint112 r0, ) = HippoxSwapPairV1(pair).getReserves();
        vm.prank(alice);
        vm.expectRevert(bytes("INSUFFICIENT_LIQUIDITY"));
        HippoxSwapPairV1(pair).flashSwap(uint256(r0), 0, address(receiver), "");
    }
    function testRouterFlashSwapForwardsCallback() public {
        vm.prank(alice);
        vm.expectRevert();
        router.flashSwap(pair, 100e18, 0, "");
    }
}
