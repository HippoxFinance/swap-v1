// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
// Environment variables
//
// Required:
//   PRIVATE_KEY             deployer private key
//   BSC_RPC_URL             BSC mainnet RPC endpoint
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {WETH} from "../src/WETH.sol";
/// @title BSC_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on BSC mainnet.
///         BSC is EVM compatible and uses WBNB as its wrapped native token.
///         WBNB exposes the same deposit / withdraw interface as WETH, so the
///         Router can use it directly without any change.
contract BSC_Deploy is Script {
    /// @notice Canonical wrapped native token address on BSC mainnet.
    ///         It is WBNB, but it exposes the same interface as WETH.
    address internal constant WETH_BSC =
        0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
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
        console.log("=== HippoxSwap BSC Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("FeeTo:", feeTo);
        console.log("Protocol fee percen:", protocolFeePercen);
        console.log("WETH (canonical on BSC):", WETH_BSC);
        if (verifyOnly) {
            console.log("VERIFY_ONLY is set, skipping broadcast");
            return (
                HippoxSwapFactoryV1(address(0)),
                HippoxSwapRouterV1(payable(address(0))),
                WETH_BSC
            );
        }
        require(owner != address(0), "ZERO_OWNER");
        require(feeTo != address(0), "ZERO_FEE_TO");
        require(protocolFeePercen <= 50, "PROTOCOL_FEE_TOO_HIGH");
        vm.startBroadcast(deployerKey);
        // Use the canonical wrapped native token on BSC.
        weth = WETH_BSC;
        // Deploy the factory with the configured owner.
        factory = new HippoxSwapFactoryV1(owner);
        // Deploy the router bound to the factory and wrapped native token.
        router = new HippoxSwapRouterV1(address(factory), address(weth));
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
