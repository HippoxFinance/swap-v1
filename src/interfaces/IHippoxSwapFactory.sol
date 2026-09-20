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
    /// @notice Emitted when the owner changes.
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
    /// @notice Unique top-level role of the factory. Can update feeTo,
    ///         protocolFeeNumerator, and transfer ownership to a new address.
    function owner() external view returns (address);
    /// @notice Address that receives the protocol fee.
    function feeTo() external view returns (address);
    /// @notice Internal protocol fee numerator, in units of 1/1000 of the AMM fee.
    ///         Read by the pair at swap time. Range: 0 to 500.
    function protocolFeeNumerator() external view returns (uint256);
    /// @notice Protocol fee numerator expressed as a percentage of the AMM fee.
    ///         Range: 0 to 50. This is the user-facing value.
    function protocolFeeNumeratorPercen() external view returns (uint256);
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
    /// @notice Creates a pair for tokenA/tokenB.
    function createPair(
        address tokenA,
        address tokenB,
        address creator
    ) external returns (address pair);
    /// @notice Creates a pair with an optional hook installed before initialize.
    function createPairWithHook(
        address tokenA,
        address tokenB,
        address creator,
        address hook
    ) external returns (address pair);
    /// @notice Updates the protocol fee as a percentage of the AMM fee.
    ///         Only owner. Range: 0 to 50. A value of 0 means the protocol
    ///         fee is disabled and the full AMM fee stays with the LPs.
    function setProtocolFeeNumeratorPercen(
        uint256 _protocolFeeNumeratorPercen
    ) external;
    /// @notice Updates the protocol fee recipient. Only owner. Cannot be zero.
    function setFeeTo(address _feeTo) external;
    /// @notice Updates the owner. Only owner.
    function setOwner(address _owner) external;
    /// @notice Paginated list of pair addresses.
    function getPairsPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory pairs);
    /// @notice Returns a full snapshot of a pair given two tokens.
    function getPairInfo(
        address tokenA,
        address tokenB
    ) external view returns (address pair, bytes memory info);
}
