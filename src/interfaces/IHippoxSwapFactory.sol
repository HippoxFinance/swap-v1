// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/// @title IHippoxSwapFactory
/// @notice Interface for the HippoxSwap factory contract.
interface IHippoxSwapFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
    /// @notice Creates a pair for tokenA/tokenB.
    /// @param tokenA First token address.
    /// @param tokenB Second token address.
    /// @param creator Address that will own the pair's creator role.
    /// @return pair Address of the newly created pair.
    function createPair(
        address tokenA,
        address tokenB,
        address creator
    ) external returns (address pair);
    /// @notice Paginated list of pair addresses.
    /// @param offset Starting index.
    /// @param limit Maximum number of addresses to return.
    /// @return pairs Slice of allPairs.
    function getPairsPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory pairs);
    /// @notice Returns a full snapshot of a pair given two tokens.
    /// @param tokenA First token address.
    /// @param tokenB Second token address.
    /// @return pair Pair address (address(0) if not found).
    /// @return info PairInfo struct (empty if pair not found).
    function getPairInfo(
        address tokenA,
        address tokenB
    ) external view returns (address pair, bytes memory info);
}
