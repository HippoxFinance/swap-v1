// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {HippoxSwapPair} from "./HippoxSwapPair.sol";
import {IHippoxSwapPair} from "./interfaces/IHippoxSwapPair.sol";
/// @title HippoxSwapFactory
/// @notice Creates and indexes one unique pair per token pair. Uses CREATE2 for deterministic addresses.
contract HippoxSwapFactory {
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );
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
    ///      Resolves the protocol fee recipient here so the pair can store it
    ///      at initialize time. If factory.feeTo is zero, the creator receives
    ///      the protocol fee (same as Uniswap V2 behavior).
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
        // The protocol fee recipient is the factory-level feeTo if set,
        // otherwise the creator. This is resolved at pair creation time and
        // stored on the pair. It can be updated later via setFeeTo on the pair.
        address protocolFeeRecipient = feeTo == address(0) ? creator : feeTo;
        // initialize now takes the hook and the protocol fee recipient.
        HippoxSwapPair(pair).initialize(
            token0,
            token1,
            creator,
            protocolFeeRecipient,
            hook,
            protocolFeeRecipient
        );
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeTo = _feeTo;
    }
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "FORBIDDEN");
        feeToSetter = _feeToSetter;
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
