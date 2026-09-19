// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactory} from "../src/HippoxSwapFactory.sol";
import {HippoxSwapRouter} from "../src/HippoxSwapRouter.sol";
import {WETH} from "../src/WETH.sol";
/// @title Deploy
/// @notice Deployment script for the HippoxSwap core contracts.
contract Deploy is Script {
    function run()
        external
        returns (HippoxSwapFactory factory, HippoxSwapRouter router, WETH weth)
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);
        weth = new WETH();
        factory = new HippoxSwapFactory(deployer);
        router = new HippoxSwapRouter(address(factory), address(weth));
        vm.stopBroadcast();
        console.log("WETH deployed at:", address(weth));
        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));
    }
}
