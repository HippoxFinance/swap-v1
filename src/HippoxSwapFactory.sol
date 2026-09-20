// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {HippoxSwapPair} from "./HippoxSwapPair.sol";
import {IHippoxSwapPair} from "./interfaces/IHippoxSwapPair.sol";
/// @title HippoxSwapFactory
/// @notice Creates and indexes one unique pair per token pair. Uses CREATE2 for deterministic addresses.
///         Also stores the protocol fee parameters so they can be controlled centrally
///         and applied uniformly to every pair created by this factory.
contract HippoxSwapFactory {
    /// @notice Address that receives the protocol fee. Can be updated by feeToSetter.
    address public feeTo;
    /// @notice Address allowed to update feeTo, feeToSetter, and the protocol fee numerator.
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    /// @notice Protocol fee numerator relative to the AMM fee.
    ///         protocolFeeNumerator / FEE_DENOMINATOR of the AMM fee is sent to feeTo.
    ///         Stored on the factory so it can be updated centrally and applied
    ///         to every pair created by this factory.
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MAX_PROTOCOL_FEE_NUMERATOR = 5;
    uint256 public protocolFeeNumerator;
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );
    /// @notice Emitted when the protocol fee numerator changes.
    event ProtocolFeeNumeratorUpdated(
        uint256 previousProtocolFeeNumerator,
        uint256 newProtocolFeeNumerator
    );
    /// @notice Emitted when the protocol fee recipient changes.
    event FeeToUpdated(address indexed previousFeeTo, address indexed newFeeTo);
    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
    /// @notice Creates a pair without a hook. Kept for backward compatibility.
    function createPair(
        address tokenA,
        address tokenB,
        address creator
    ) external returns (address pair) {
        return _createPair(tokenA, tokenB, creator, address(0));
    }
    /// @notice Creates a pair with an optional hook installed before initialize.
    /// @dev Passing the hook address into initialize allows beforeInitialize and
    ///      afterInitialize to actually fire.
    function createPairWithHook(
        address tokenA,
        address tokenB,
        address creator,
        address hook
    ) external returns (address pair) {
        return _createPair(tokenA, tokenB, creator, hook);
    }
    /// @dev Internal pair creation shared by both public entry points.
    ///      The protocol fee parameters live on the factory and are read by
    ///      the pair at swap time, so nothing protocol-fee-related is stored
    ///      on the pair. The pair stores the factory address so it can look
    ///      up the parameters on each swap.
    ///      The trading tax recipient is the creator, so that the trading tax
    ///      and the protocol fee can be routed to different addresses.
    function _createPair(
        address tokenA,
        address tokenB,
        address creator,
        address hook
    ) internal returns (address pair) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(creator != address(0), "ZERO_CREATOR");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");
        bytes memory bytecode = type(HippoxSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // The trading tax recipient is the creator. It can be updated later
        // via setTaxRecipient on the pair by the pair's admin.
        address tradingTaxRecipient = creator;
        // The factory passes its own address to the pair so the pair can read
        // the protocol fee parameters at swap time.
        HippoxSwapPair(pair).initialize(
            token0,
            token1,
            creator,
            tradingTaxRecipient,
            hook,
            address(this)
        );
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    /// @notice Updates the protocol fee recipient. Only feeToSetter.
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        address previous = feeTo;
        feeTo = _feeTo;
        emit FeeToUpdated(previous, _feeTo);
    }
    /// @notice Updates the feeToSetter. Only feeToSetter.
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
    /// @notice Updates the protocol fee numerator. Only feeToSetter.
    /// @dev The new value applies to every pair created by this factory,
    ///      because pairs read this value at swap time.
    function setProtocolFeeNumerator(uint256 _protocolFeeNumerator) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        require(
            _protocolFeeNumerator <= MAX_PROTOCOL_FEE_NUMERATOR,
            "PROTOCOL_FEE_TOO_HIGH"
        );
        uint256 previous = protocolFeeNumerator;
        protocolFeeNumerator = _protocolFeeNumerator;
        emit ProtocolFeeNumeratorUpdated(previous, _protocolFeeNumerator);
    }
    // Extended read functions
    /// @notice Paginated list of pair addresses.
    function getPairsPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory pairs) {
        uint256 total = allPairs.length;
        if (offset >= total) {
            return new address[](0);
        }
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        pairs = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            pairs[i - offset] = allPairs[i];
        }
    }
    /// @notice Returns a full snapshot of a pair given two tokens.
    function getPairInfo(
        address tokenA,
        address tokenB
    ) external view returns (address pair, bytes memory info) {
        pair = getPair[tokenA][tokenB];
        if (pair == address(0)) {
            return (address(0), "");
        }
        IHippoxSwapPair.PairInfo memory pi = IHippoxSwapPair(pair)
            .getPairInfo();
        info = abi.encode(pi);
    }
}
