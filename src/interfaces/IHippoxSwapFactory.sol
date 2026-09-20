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
    /// @notice Emitted when the protocol fee numerator changes.
    event ProtocolFeeNumeratorUpdated(
        uint256 previousProtocolFeeNumerator,
        uint256 newProtocolFeeNumerator
    );
    /// @notice Emitted when the protocol fee recipient changes.
    event FeeToUpdated(address indexed previousFeeTo, address indexed newFeeTo);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    /// @notice Protocol fee numerator, applied as a fraction of the AMM fee.
    ///         Stored on the factory so it can be controlled centrally and
    ///         applied uniformly to every pair created by this factory.
    function protocolFeeNumerator() external view returns (uint256);
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
    /// @notice Creates a pair with an optional hook installed before initialize.
    /// @dev The hook address is passed into initialize so that beforeInitialize
    ///      and afterInitialize can actually fire.
    /// @param tokenA First token address.
    /// @param tokenB Second token address.
    /// @param creator Address that will own the pair's creator role.
    /// @param hook Hook address, or address(0) for no hook.
    /// @return pair Address of the newly created pair.
    function createPairWithHook(
        address tokenA,
        address tokenB,
        address creator,
        address hook
    ) external returns (address pair);
    /// @notice Updates the protocol fee numerator. Only feeToSetter.
    function setProtocolFeeNumerator(uint256 _protocolFeeNumerator) external;
    /// @notice Updates the protocol fee recipient. Only feeToSetter.
    function setFeeTo(address _feeTo) external;
    /// @notice Updates the feeToSetter. Only feeToSetter.
    function setFeeToSetter(address _feeToSetter) external;
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
