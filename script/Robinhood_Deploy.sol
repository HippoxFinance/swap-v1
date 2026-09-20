// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
// Environment variables
//
// Required:
//   PRIVATE_KEY             deployer private key
//   ROBINHOOD_RPC_URL       Robinhood Chain mainnet RPC endpoint
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {WETH} from "../src/WETH.sol";
/// @title Robinhood_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on Robinhood Chain mainnet.
///         Robinhood Chain is an EVM-compatible Arbitrum L2 that uses ETH as gas.
contract Robinhood_Deploy is Script {
    /// @notice Canonical WETH address on Robinhood Chain mainnet.
    address internal constant WETH_ROBINHOOD =
        0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    function run()
        external
        returns (
            HippoxSwapFactoryV1 factory,
            HippoxSwapRouterV1 router,
            address weth
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address owner = vm.envOr("OWNER", deployer);
        address feeTo = vm.envOr("FEE_TO", owner);
        uint256 protocolFeePercen = vm.envOr("PROTOCOL_FEE_PERCEN", uint256(0));
        bool verifyOnly = vm.envOr("VERIFY_ONLY", false);
        console.log("=== HippoxSwap Robinhood Chain Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("FeeTo:", feeTo);
        console.log("Protocol fee percen:", protocolFeePercen);
        console.log("WETH (canonical):", WETH_ROBINHOOD);
        if (verifyOnly) {
            console.log("VERIFY_ONLY is set, skipping broadcast");
            return (
                HippoxSwapFactoryV1(address(0)),
                HippoxSwapRouterV1(payable(address(0))),
                WETH_ROBINHOOD
            );
        }
        require(owner != address(0), "ZERO_OWNER");
        require(feeTo != address(0), "ZERO_FEE_TO");
        require(protocolFeePercen <= 50, "PROTOCOL_FEE_TOO_HIGH");
        vm.startBroadcast(deployerKey);
        weth = WETH_ROBINHOOD;
        factory = new HippoxSwapFactoryV1(owner);
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        vm.stopBroadcast();
        if (deployer == owner) {
            vm.startBroadcast(deployerKey);
            if (feeTo != owner) {
                factory.setFeeTo(feeTo);
            }
            if (protocolFeePercen != 0) {
                factory.setProtocolFeeNumeratorPercen(protocolFeePercen);
            }
            vm.stopBroadcast();
        }
        console.log("=== Deployment complete ===");
        console.log("WETH:", weth);
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
    }
}
