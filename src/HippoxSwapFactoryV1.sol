// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {HippoxSwapPairV1} from "./HippoxSwapPairV1.sol";
import {IHippoxSwapPairV1} from "./interfaces/IHippoxSwapPairV1.sol";
/// @title HippoxSwapFactoryV1
/// @notice Creates and indexes one unique pair per token pair. Uses CREATE2 for deterministic addresses.
///         Also stores the protocol fee parameters so they can be controlled centrally
///         and applied uniformly to every pair created by this factory.
contract HippoxSwapFactoryV1 {
    /// @notice Unique top-level role of the factory. Can update feeTo,
    ///         protocolFeeNumeratorPercen, and transfer ownership to a new address.
    address public owner;
    /// @notice Address that receives the protocol fee. Defaults to the owner
    ///         at deployment time. Cannot be set to address(0).
    address public feeTo;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    /// @notice Internal protocol fee numerator, in units of 1/1000 of the AMM fee.
    ///         protocolFeeNumerator / FEE_DENOMINATOR of the AMM fee is sent to feeTo.
    ///         Stored on the factory so it can be updated centrally and applied
    ///         to every pair created by this factory.
    ///         A value of 0 means no protocol fee is collected and all of the
    ///         AMM fee stays with the LPs.
    ///         MAX_PROTOCOL_FEE_NUMERATOR is 500, meaning the protocol can take
    ///         up to 50% of the AMM fee (500 / 1000).
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MAX_PROTOCOL_FEE_NUMERATOR = 500;
    uint256 public protocolFeeNumerator;
    /// @notice User-facing maximum, expressed as a percentage of the AMM fee.
    ///         Must correspond to MAX_PROTOCOL_FEE_NUMERATOR.
    uint256 public constant MAX_PROTOCOL_FEE_PERCEN = 50;
    /// @notice Denominator used to convert between percentage and the internal
    ///         numerator. 100 percent maps to FEE_DENOMINATOR internal units.
    uint256 public constant PERCENT_DENOMINATOR = 100;
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
    /// @notice Emitted when the owner changes.
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }
    /// @param _owner Initial owner of the factory. Also becomes the initial
    ///               protocol fee recipient (feeTo). The initial
    ///               protocol fee is set to 0.5% of the AMM fee.
    constructor(address _owner) {
        require(_owner != address(0), "ZERO_OWNER");
        owner = _owner;
        feeTo = _owner;
        // 0.5% expressed in 1/1000 units of the AMM fee.
        protocolFeeNumerator = 5;
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
        bytes memory bytecode = type(HippoxSwapPairV1).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // The trading tax recipient is the creator. It can be updated later
        // via setTaxRecipient on the pair by the pair's admin.
        address tradingTaxRecipient = creator;
        // The factory passes its own address to the pair so the pair can read
        // the protocol fee parameters at swap time.
        HippoxSwapPairV1(pair).initialize(
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
    /// @notice Updates the protocol fee recipient. Only owner.
    /// @dev feeTo cannot be set to address(0), because a zero recipient would
    ///      silently drop the protocol fee.
    function setFeeTo(address _feeTo) external onlyOwner {
        require(_feeTo != address(0), "ZERO_FEE_TO");
        address previous = feeTo;
        feeTo = _feeTo;
        emit FeeToUpdated(previous, _feeTo);
    }
    /// @notice Updates the protocol fee as a percentage of the AMM fee.
    ///         Only owner. Range: 0 to 50. A value of 0 means the protocol
    ///         fee is disabled and the full AMM fee stays with the LPs.
    /// @dev The percentage is converted to the internal numerator by
    ///      multiplying by FEE_DENOMINATOR / PERCENT_DENOMINATOR, which is 10.
    ///      The new value applies to every pair created by this factory,
    ///      because pairs read the internal numerator at swap time.
    function setProtocolFeeNumeratorPercen(
        uint256 _protocolFeeNumeratorPercen
    ) external onlyOwner {
        require(
            _protocolFeeNumeratorPercen <= MAX_PROTOCOL_FEE_PERCEN,
            "PROTOCOL_FEE_TOO_HIGH"
        );
        uint256 previous = protocolFeeNumerator;
        // Convert percentage to the internal numerator.
        // 1 percent = 1/100 of the AMM fee = 10/1000 of the AMM fee.
        uint256 newNumerator = (_protocolFeeNumeratorPercen * FEE_DENOMINATOR) /
            PERCENT_DENOMINATOR;
        protocolFeeNumerator = newNumerator;
        emit ProtocolFeeNumeratorUpdated(previous, newNumerator);
    }
    /// @notice Updates the owner. Only owner.
    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "ZERO_OWNER");
        address previous = owner;
        owner = _owner;
        emit OwnerUpdated(previous, _owner);
    }
    /// @notice Returns the protocol fee as a percentage of the AMM fee.
    /// @dev Computed from the internal numerator. Range: 0 to 50.
    function protocolFeeNumeratorPercen() public view returns (uint256) {
        return (protocolFeeNumerator * PERCENT_DENOMINATOR) / FEE_DENOMINATOR;
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
        IHippoxSwapPairV1.PairInfo memory pi = IHippoxSwapPairV1(pair)
            .getPairInfo();
        info = abi.encode(pi);
    }
}
