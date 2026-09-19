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
    function createPair(
        address tokenA,
        address tokenB,
        address creator
    ) external returns (address pair) {
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
        address recipient = feeTo == address(0) ? creator : feeTo;
        HippoxSwapPair(pair).initialize(token0, token1, creator, recipient);
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
    /// @param offset Starting index.
    /// @param limit Maximum number of addresses to return.
    /// @return pairs Slice of allPairs.
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
    /// @dev Returns address(0) and empty bytes if the pair does not exist.
    ///      Callers should decode `info` as IHippoxSwapPair.PairInfo.
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
