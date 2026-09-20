// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IHippoxSwapPair} from "./interfaces/IHippoxSwapPair.sol";
import {IHippoxSwapHook} from "./interfaces/IHippoxSwapHook.sol";
/// @title HippoxSwapPair
/// @notice Constant-product AMM pair for HippoxSwap V1. Holds two token reserves and executes swaps.
/// @dev Deployed by HippoxSwapFactory via CREATE2, then initialized once.
///      All operations rely on balance differences. Callers must transfer tokens in before mint/swap,
///      and transfer LP tokens in before burn.
///      This version also implements an on-chain native TWAP oracle (Uniswap V2 style cumulative prices).
contract HippoxSwapPair is ERC20 {
    // State
    IERC20 public token0;
    IERC20 public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    bool private initialized;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    // AMM fee (adjustable)
    uint256 public constant DEFAULT_FEE_NUMERATOR = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MAX_FEE_NUMERATOR = 10;
    uint256 public feeNumerator = DEFAULT_FEE_NUMERATOR;
    // Roles and trading tax
    address public creator;
    address public admin;
    uint256 public constant DEFAULT_TAX_BPS = 10;
    uint256 public constant MAX_TAX_BPS = 100;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public taxBps = DEFAULT_TAX_BPS;
    address public taxRecipient;
    // Hook
    /// @notice Optional hook contract. address(0) means disabled.
    address public hook;
    /// @notice Simple reentrancy lock.
    bool private locked;
    // TWAP Oracle state
    /// @notice Cumulative price of token0 in terms of token1, multiplied by 2**112.
    /// @dev price0 = reserve1 / reserve0. Cumulative value is price0 * timeElapsed.
    uint256 public price0CumulativeLast;
    /// @notice Cumulative price of token1 in terms of token0, multiplied by 2**112.
    /// @dev price1 = reserve0 / reserve1. Cumulative value is price1 * timeElapsed.
    uint256 public price1CumulativeLast;
    /// @notice Timestamp of the last oracle update.
    uint32 public blockTimestampLast;
    // Events
    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);
    event TaxUpdated(uint256 previousTaxBps, uint256 newTaxBps);
    event TaxRecipientUpdated(
        address indexed previousRecipient,
        address indexed newRecipient
    );
    event FeeUpdated(uint256 previousFeeNumerator, uint256 newFeeNumerator);
    event HookUpdated(address indexed previousHook, address indexed newHook);
    event HookCallFailed(address indexed hook, string reason);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    modifier onlyCreator() {
        require(msg.sender == creator, "ONLY_CREATOR");
        _;
    }
    modifier onlyAdmin() {
        require(msg.sender == admin, "ONLY_ADMIN");
        _;
    }
    /// @dev Prevents reentrancy into swap.
    modifier nonReentrant() {
        require(!locked, "REENTRANT");
        locked = true;
        _;
        locked = false;
    }
    // Constructor
    constructor() ERC20("Hippox LP Token", "HIP-LP") {}
    /// @notice One-time initializer called by the factory after CREATE2 deployment.
    function initialize(
        address _token0,
        address _token1,
        address _creator,
        address _taxRecipient
    ) external {
        require(!initialized, "ALREADY_INITIALIZED");
        require(_token0 != address(0) && _token1 != address(0), "ZERO_ADDRESS");
        require(_token0 != _token1, "IDENTICAL_ADDRESSES");
        initialized = true;
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        creator = _creator;
        admin = _creator;
        taxRecipient = _taxRecipient == address(0) ? _creator : _taxRecipient;
    }
    // Role management
    function setAdmin(address _newAdmin) external onlyCreator {
        require(_newAdmin != address(0), "ZERO_ADDRESS");
        address previous = admin;
        admin = _newAdmin;
        emit AdminUpdated(previous, _newAdmin);
    }
    function setTaxBps(uint256 _taxBps) external onlyAdmin {
        require(_taxBps <= MAX_TAX_BPS, "TAX_TOO_HIGH");
        uint256 previous = taxBps;
        taxBps = _taxBps;
        emit TaxUpdated(previous, _taxBps);
    }
    function setTaxRecipient(address _recipient) external onlyAdmin {
        require(_recipient != address(0), "ZERO_ADDRESS");
        address previous = taxRecipient;
        taxRecipient = _recipient;
        emit TaxRecipientUpdated(previous, _recipient);
    }
    function setFeeNumerator(uint256 _feeNumerator) external onlyAdmin {
        require(_feeNumerator <= MAX_FEE_NUMERATOR, "FEE_TOO_HIGH");
        uint256 previous = feeNumerator;
        feeNumerator = _feeNumerator;
        emit FeeUpdated(previous, _feeNumerator);
    }
    // Hook management
    /// @notice Sets or clears the hook. Only the creator can call this.
    /// @param _hook New hook address, or address(0) to disable.
    function setHook(address _hook) external onlyCreator {
        address previous = hook;
        hook = _hook;
        emit HookUpdated(previous, _hook);
    }
    // Views
    /// @notice Returns the current reserves of the pair.
    function getReserves() public view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }
    /// @notice Aggregated snapshot of pair state.
    function getPairInfo()
        external
        view
        returns (IHippoxSwapPair.PairInfo memory info)
    {
        info = IHippoxSwapPair.PairInfo({
            token0: address(token0),
            token1: address(token1),
            reserve0: reserve0,
            reserve1: reserve1,
            feeNumerator: feeNumerator,
            feeDenominator: FEE_DENOMINATOR,
            maxFeeNumerator: MAX_FEE_NUMERATOR,
            taxBps: taxBps,
            maxTaxBps: MAX_TAX_BPS,
            bpsDenominator: BPS_DENOMINATOR,
            taxRecipient: taxRecipient,
            totalSupply: totalSupply(),
            creator: creator,
            admin: admin,
            minimumLiquidity: MINIMUM_LIQUIDITY,
            hook: hook
        });
    }
    /// @notice Single-pool quote including AMM fee and trading tax.
    function getAmountOut(
        uint256 amountIn,
        address tokenIn
    ) external view returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(
            tokenIn == address(token0) || tokenIn == address(token1),
            "INVALID_TOKEN"
        );
        bool isToken0 = tokenIn == address(token0);
        uint256 reserveIn = isToken0 ? reserve0 : reserve1;
        uint256 reserveOut = isToken0 ? reserve1 : reserve0;
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 tax = (amountIn * taxBps) / BPS_DENOMINATOR;
        uint256 effectiveIn = amountIn - tax;
        uint256 amountInWithFee = effectiveIn *
            (FEE_DENOMINATOR - feeNumerator);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        amountOut = numerator / denominator;
    }
    // Oracle views
    /// @notice Returns the cumulative prices and the last update timestamp.
    /// @return _price0CumulativeLast Cumulative price of token0 (price0 * time).
    /// @return _price1CumulativeLast Cumulative price of token1 (price1 * time).
    /// @return _blockTimestampLast Last oracle update timestamp.
    function getCumulativePrices()
        external
        view
        returns (
            uint256 _price0CumulativeLast,
            uint256 _price1CumulativeLast,
            uint32 _blockTimestampLast
        )
    {
        return (price0CumulativeLast, price1CumulativeLast, blockTimestampLast);
    }
    /// @notice Computes the time-weighted average price of tokenIn in terms of tokenOut.
    /// @dev This is a helper for external consumers. It uses the cumulative values
    ///      stored at two points in time. Callers must pass valid snapshots.
    /// @param tokenIn Input token address (must be token0 or token1).
    /// @param amountIn Amount of tokenIn to price.
    /// @param priceCumulativeLastThen Cumulative value of tokenIn at the earlier timestamp.
    /// @param priceCumulativeLastNow Cumulative value of tokenIn at the later timestamp.
    /// @param timeElapsed Elapsed seconds between the two snapshots. Must be > 0.
    /// @return amountOut TWAP-based output amount.
    function consult(
        address tokenIn,
        uint256 amountIn,
        uint256 priceCumulativeLastThen,
        uint256 priceCumulativeLastNow,
        uint32 timeElapsed
    ) external view returns (uint256 amountOut) {
        require(timeElapsed > 0, "INSUFFICIENT_ELAPSED_TIME");
        require(
            tokenIn == address(token0) || tokenIn == address(token1),
            "INVALID_TOKEN"
        );
        // priceCumulative is stored as price * 2**112.
        // Average price = (cumulativeNow - cumulativeThen) / timeElapsed / 2**112.
        uint256 priceAverageX112 = (priceCumulativeLastNow -
            priceCumulativeLastThen) / timeElapsed;
        amountOut = (amountIn * priceAverageX112) >> 112;
    }
    // Liquidity: mint
    function mint(address to) external returns (uint256 liquidity) {
        require(initialized, "NOT_INITIALIZED");
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            liquidity = _min(
                (amount0 * _totalSupply) / reserve0,
                (amount1 * _totalSupply) / reserve1
            );
        }
        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }
    // Liquidity: burn
    function burn(
        address to
    ) external returns (uint256 amount0, uint256 amount1) {
        require(initialized, "NOT_INITIALIZED");
        uint256 liquidity = balanceOf(address(this));
        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * token0.balanceOf(address(this))) / _totalSupply;
        amount1 = (liquidity * token1.balanceOf(address(this))) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        token0.transfer(to, amount0);
        token1.transfer(to, amount1);
        _update(
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        emit Burn(msg.sender, amount0, amount1, to);
    }
    // Swap
    /// @notice Execute a swap against the pair.
    /// @dev Hook is called before and after the swap with a single SwapContext
    ///      struct. Hook failures never block the swap; they are caught and
    ///      emitted as HookCallFailed events.
    /// @dev The constant-product check is inlined to reduce local variables and
    ///      avoid "stack too deep" at compile time.
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external nonReentrant {
        require(initialized, "NOT_INITIALIZED");
        require(amount0Out > 0 || amount1Out > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            amount0Out < reserve0 && amount1Out < reserve1,
            "INSUFFICIENT_LIQUIDITY"
        );
        require(to != address(0), "ZERO_ADDRESS");
        // Snapshot reserves before the swap for the hook.
        uint112 reserve0Before = reserve0;
        uint112 reserve1Before = reserve1;
        // Send output tokens first.
        if (amount0Out > 0) token0.transfer(to, amount0Out);
        if (amount1Out > 0) token1.transfer(to, amount1Out);
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        // Determine input amounts from balance differences.
        uint256 amount0In = balance0 > reserve0 - amount0Out
            ? balance0 - (reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out
            ? balance1 - (reserve1 - amount1Out)
            : 0;
        require(amount0In > 0 || amount1In > 0, "INSUFFICIENT_INPUT_AMOUNT");
        // Deduct trading tax from input amounts and send to taxRecipient.
        if (taxBps > 0 && taxRecipient != address(0)) {
            if (amount0In > 0) {
                uint256 tax0 = (amount0In * taxBps) / BPS_DENOMINATOR;
                if (tax0 > 0) {
                    token0.transfer(taxRecipient, tax0);
                    balance0 -= tax0;
                    amount0In -= tax0;
                }
            }
            if (amount1In > 0) {
                uint256 tax1 = (amount1In * taxBps) / BPS_DENOMINATOR;
                if (tax1 > 0) {
                    token1.transfer(taxRecipient, tax1);
                    balance1 -= tax1;
                    amount1In -= tax1;
                }
            }
        }
        // Build the hook context once. reserve0After / reserve1After are
        // filled in after _update. Using a single struct avoids stack-too-deep.
        IHippoxSwapHook.SwapContext memory ctx = IHippoxSwapHook.SwapContext({
            sender: msg.sender,
            txOrigin: tx.origin,
            token0: address(token0),
            token1: address(token1),
            amount0In: amount0In,
            amount1In: amount1In,
            amount0Out: amount0Out,
            amount1Out: amount1Out,
            reserve0Before: reserve0Before,
            reserve1Before: reserve1Before,
            reserve0After: 0,
            reserve1After: 0,
            feeNumerator: feeNumerator,
            taxBps: taxBps,
            totalSupply: totalSupply(),
            blockNumber: block.number,
            blockTimestamp: block.timestamp,
            gasPrice: tx.gasprice,
            gasLeft: gasleft()
        });
        // Call beforeSwap hook with the context.
        _callBeforeSwap(ctx);
        // Constant product check.
        require(
            (balance0 * FEE_DENOMINATOR - amount0In * feeNumerator) *
                (balance1 * FEE_DENOMINATOR - amount1In * feeNumerator) >=
                (uint256(reserve0Before) - amount0Out) *
                    (uint256(reserve1Before) - amount1Out) *
                    FEE_DENOMINATOR ** 2,
            "K"
        );
        _update(balance0, balance1);
        // Fill in post-swap reserves and call afterSwap.
        ctx.reserve0After = reserve0;
        ctx.reserve1After = reserve1;
        _callAfterSwap(ctx);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    // Hook call helpers
    /// @dev Calls beforeSwap. Swallows revert to keep the swap live.
    function _callBeforeSwap(IHippoxSwapHook.SwapContext memory ctx) private {
        address h = hook;
        if (h == address(0)) return;
        try IHippoxSwapHook(h).beforeSwap(ctx) {} catch Error(
            string memory reason
        ) {
            emit HookCallFailed(h, reason);
        } catch {
            emit HookCallFailed(h, "beforeSwap failed");
        }
    }
    /// @dev Calls afterSwap. Swallows revert to keep the swap live.
    function _callAfterSwap(IHippoxSwapHook.SwapContext memory ctx) private {
        address h = hook;
        if (h == address(0)) return;
        try IHippoxSwapHook(h).afterSwap(ctx) {} catch Error(
            string memory reason
        ) {
            emit HookCallFailed(h, reason);
        } catch {
            emit HookCallFailed(h, "afterSwap failed");
        }
    }
    // Internal helpers
    /// @dev Updates reserves and accumulates TWAP oracle prices.
    ///      The cumulative values are based on the post-tax balances, so the
    ///      trading tax does not distort the oracle.
    function _update(uint256 balance0, uint256 balance1) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            "OVERFLOW"
        );
        // TWAP accumulation
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        // Only accumulate if time has passed and reserves are non-zero.
        // The first update (blockTimestampLast == 0) only sets the timestamp.
        if (
            timeElapsed > 0 &&
            reserve0 != 0 &&
            reserve1 != 0 &&
            blockTimestampLast != 0
        ) {
            // price0 = reserve1 / reserve0, scaled by 2**112.
            // price1 = reserve0 / reserve1, scaled by 2**112.
            price0CumulativeLast +=
                ((uint256(reserve1) << 112) / reserve0) *
                timeElapsed;
            price1CumulativeLast +=
                ((uint256(reserve0) << 112) / reserve1) *
                timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
