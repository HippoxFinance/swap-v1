// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/// @title MockToken
/// @notice Minimal ERC20 with a public mint, used only by the local deployment
///         script and local tests. Not part of the production contracts.
contract MockToken is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}
    /// @notice Mints `amount` tokens to `to`. Anyone can call this.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
