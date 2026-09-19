// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/// @title WETH
/// @notice Minimal Wrapped Ether implementation for local testing and deployment.
contract WETH is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    constructor() ERC20("Wrapped Ether", "WETH") {}
    receive() external payable {
        deposit();
    }
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    function withdraw(uint256 wad) external {
        require(balanceOf(msg.sender) >= wad, "INSUFFICIENT_BALANCE");
        _burn(msg.sender, wad);
        (bool ok, ) = msg.sender.call{value: wad}("");
        require(ok, "ETH_TRANSFER_FAILED");
        emit Withdrawal(msg.sender, wad);
    }
}
