// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxOracleV1} from "../src/HippoxOracleV1.sol";
import {WETH} from "../src/WETH.sol";
/// @title Robinhood_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on Robinhood Chain mainnet.
///         Robinhood Chain is an EVM-compatible Arbitrum L2 that uses ETH as gas.
///         All configuration is defined as constants at the top of this file.
contract Robinhood_Deploy is Script {
    // Configuration
    /// @notice RPC endpoint of Robinhood Chain mainnet. Used for reference only.
    string internal constant RPC_URL =
        "https://rpc.mainnet.chain.robinhood.com";
    /// @notice Canonical WETH address on Robinhood Chain mainnet.
    address internal constant WETH_ROBINHOOD =
        0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    /// @dev Deployer private key. Fill in before running.
    uint256 internal constant DEPLOYER_PRIVATE_KEY = 0x0;
    /// @notice Owner of the factory. Defaults to the deployer if set to address(0).
    address internal constant OWNER = address(0);
    /// @notice Protocol fee recipient. Defaults to the owner if set to address(0).
    address internal constant FEE_TO = address(0);
    /// @notice Initial protocol fee as a percentage of the AMM fee.
    ///         Range: 0 to 50. 0 disables the protocol fee.
    uint256 internal constant PROTOCOL_FEE_PERCEN = 0;
    /// @notice When true, only prints the intended configuration and skips broadcast.
    bool internal constant VERIFY_ONLY = false;
    /// @notice When true, deploys an oracle bound to the factory as a placeholder.
    bool internal constant DEPLOY_ORACLE = true;
    // Deployment
    function run()
        external
        returns (
            HippoxSwapFactoryV1 factory,
            HippoxSwapRouterV1 router,
            address weth,
            HippoxOracleV1 oracle
        )
    {
        address deployer = vm.addr(DEPLOYER_PRIVATE_KEY);
        address resolvedOwner = OWNER == address(0) ? deployer : OWNER;
        address resolvedFeeTo = FEE_TO == address(0) ? resolvedOwner : FEE_TO;
        console.log("=== HippoxSwap Robinhood Chain Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", resolvedOwner);
        console.log("FeeTo:", resolvedFeeTo);
        console.log("Protocol fee percen:", PROTOCOL_FEE_PERCEN);
        console.log("WETH (canonical):", WETH_ROBINHOOD);
        if (VERIFY_ONLY) {
            console.log("VERIFY_ONLY is set, skipping broadcast");
            return (
                HippoxSwapFactoryV1(address(0)),
                HippoxSwapRouterV1(payable(address(0))),
                WETH_ROBINHOOD,
                HippoxOracleV1(address(0))
            );
        }
        require(resolvedOwner != address(0), "ZERO_OWNER");
        require(resolvedFeeTo != address(0), "ZERO_FEE_TO");
        require(PROTOCOL_FEE_PERCEN <= 50, "PROTOCOL_FEE_TOO_HIGH");
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        weth = WETH_ROBINHOOD;
        factory = new HippoxSwapFactoryV1(resolvedOwner);
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        if (DEPLOY_ORACLE) {
            oracle = new HippoxOracleV1(address(factory));
        }
        vm.stopBroadcast();
        if (deployer == resolvedOwner) {
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
            if (resolvedFeeTo != resolvedOwner) {
                factory.setFeeTo(resolvedFeeTo);
            }
            if (PROTOCOL_FEE_PERCEN != 0) {
                factory.setProtocolFeeNumeratorPercen(PROTOCOL_FEE_PERCEN);
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
        if (DEPLOY_ORACLE) {
            console.log("Oracle:", address(oracle));
        } else {
            console.log("Oracle: not deployed");
        }
        console.log("Owner:", resolvedOwner);
        console.log("FeeTo:", factory.feeTo());
        console.log(
            "Protocol fee percen:",
            factory.protocolFeeNumeratorPercen()
        );
    }
}
