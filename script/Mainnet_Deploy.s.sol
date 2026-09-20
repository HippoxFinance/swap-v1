// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxOracleV1} from "../src/HippoxOracleV1.sol";
import {WETH} from "../src/WETH.sol";
/// @title Mainnet_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on Ethereum mainnet.
///         All configuration is defined as constants at the top of this file.
contract Mainnet_Deploy is Script {
    // Configuration
    /// @notice RPC endpoint of Ethereum mainnet. Used for reference only.
    string internal constant RPC_URL =
        "https://eth-mainnet.g.alchemy.com/v2/...";
    /// @notice Canonical WETH address on Ethereum mainnet.
    address internal constant WETH_MAINNET =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
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
    /// @notice When true, deploys an oracle bound to the first pair created.
    ///         On mainnet the pair does not exist yet, so the oracle is
    ///         deployed with the factory address as a placeholder and can
    ///         be re-pointed later.
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
        console.log("=== HippoxSwap Mainnet Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", resolvedOwner);
        console.log("FeeTo:", resolvedFeeTo);
        console.log("Protocol fee percen:", PROTOCOL_FEE_PERCEN);
        console.log("WETH (canonical):", WETH_MAINNET);
        if (VERIFY_ONLY) {
            console.log("VERIFY_ONLY is set, skipping broadcast");
            return (
                HippoxSwapFactoryV1(address(0)),
                HippoxSwapRouterV1(payable(address(0))),
                WETH_MAINNET,
                HippoxOracleV1(address(0))
            );
        }
        require(resolvedOwner != address(0), "ZERO_OWNER");
        require(resolvedFeeTo != address(0), "ZERO_FEE_TO");
        require(PROTOCOL_FEE_PERCEN <= 50, "PROTOCOL_FEE_TOO_HIGH");
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        weth = WETH_MAINNET;
        factory = new HippoxSwapFactoryV1(resolvedOwner);
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        // On mainnet there are no pairs yet, so the oracle cannot be bound to
        // a real pair at deployment time. When DEPLOY_ORACLE is true, the
        // oracle is deployed with the factory address as a placeholder. The
        // oracle can be redeployed later once the first pair is created.
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
