// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
// Environment variables
//
// Required:
//   PRIVATE_KEY             deployer private key
//   BASE_RPC_URL            Base mainnet RPC endpoint
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactory} from "../src/HippoxSwapFactory.sol";
import {HippoxSwapRouter} from "../src/HippoxSwapRouter.sol";
import {WETH} from "../src/WETH.sol";
/// @title Base_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on Base mainnet.
///         Uses the canonical WETH address on Base, and reads the owner address,
///         protocol fee settings, and initial feeTo from environment variables
///         so that mainnet deployment does not depend on hard-coded values.
contract Base_Deploy is Script {
    /// @notice Canonical WETH address on Base mainnet.
    address internal constant WETH_BASE =
        0x4200000000000000000000000000000000000006;
    function run()
        external
        returns (
            HippoxSwapFactory factory,
            HippoxSwapRouter router,
            address weth
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        // Owner of the factory. Defaults to the deployer if not provided.
        address owner = vm.envOr("OWNER", deployer);
        // Initial protocol fee recipient. Defaults to the owner.
        address feeTo = vm.envOr("FEE_TO", owner);
        // Initial protocol fee, expressed as a percentage of the AMM fee.
        // 0 means the protocol fee is disabled. Max is 50.
        uint256 protocolFeePercen = vm.envOr("PROTOCOL_FEE_PERCEN", uint256(0));
        // Optional verify-only flag. When set to true, the script only prints
        // the intended addresses and does not broadcast.
        bool verifyOnly = vm.envOr("VERIFY_ONLY", false);
        console.log("=== HippoxSwap Base Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("FeeTo:", feeTo);
        console.log("Protocol fee percen:", protocolFeePercen);
        console.log("WETH (canonical):", WETH_BASE);
        if (verifyOnly) {
            console.log("VERIFY_ONLY is set, skipping broadcast");
            return (
                HippoxSwapFactory(address(0)),
                HippoxSwapRouter(payable(address(0))),
                WETH_BASE
            );
        }
        require(owner != address(0), "ZERO_OWNER");
        require(feeTo != address(0), "ZERO_FEE_TO");
        require(protocolFeePercen <= 50, "PROTOCOL_FEE_TOO_HIGH");
        vm.startBroadcast(deployerKey);
        // Use the canonical WETH on Base. Do not deploy a new one.
        weth = WETH_BASE;
        // Deploy the factory with the configured owner.
        factory = new HippoxSwapFactory(owner);
        // Deploy the router bound to the factory and WETH.
        router = new HippoxSwapRouter(address(factory), address(weth));
        vm.stopBroadcast();
        // Apply initial protocol fee settings. These calls are broadcast by
        // the owner, so they are executed after the deployment as part of the
        // same broadcast session only if the deployer is also the owner.
        // Otherwise they must be executed separately by the owner.
        if (deployer == owner) {
            vm.startBroadcast(deployerKey);
            if (feeTo != owner) {
                factory.setFeeTo(feeTo);
            }
            if (protocolFeePercen != 0) {
                factory.setProtocolFeeNumeratorPercen(protocolFeePercen);
            }
            vm.stopBroadcast();
        } else {
            console.log(
                "Deployer is not the owner. Call setFeeTo / setProtocolFeeNumeratorPercen from the owner account."
            );
        }
        console.log("=== Deployment complete ===");
        console.log("WETH:", weth);
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
        console.log("Owner:", owner);
        console.log("FeeTo:", factory.feeTo());
        console.log(
            "Protocol fee percen:",
            factory.protocolFeeNumeratorPercen()
        );
    }
}
