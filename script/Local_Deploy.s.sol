// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {WETH} from "../src/WETH.sol";
/// @title Local_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on a local anvil chain.
contract Local_Deploy is Script {
    function run()
        external
        returns (
            WETH weth,
            HippoxSwapFactoryV1 factory,
            HippoxSwapRouterV1 router
        )
    {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0x0));
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);
        weth = new WETH();
        factory = new HippoxSwapFactoryV1(deployer);
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        vm.stopBroadcast();
        console.log("WETH:", address(weth));
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
    }
}
