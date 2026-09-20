// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;
import {Script, console} from "forge-std/Script.sol";
import {HippoxSwapFactoryV1} from "../src/HippoxSwapFactoryV1.sol";
import {HippoxSwapRouterV1} from "../src/HippoxSwapRouterV1.sol";
import {HippoxOracleV1} from "../src/HippoxOracleV1.sol";
import {WETH} from "../src/WETH.sol";
import {MockToken} from "./mock/MockToken.sol";
import {MockHook} from "./mock/MockHook.sol";
/// @title Local_Deploy
/// @notice Deployment script for the HippoxSwap core contracts on a local anvil chain.
///         Also deploys two mock ERC20 tokens, an oracle bound to the pair,
///         and a mock hook for the SDK hook tests.
///         All configuration is defined as constants at the top of this file.
contract Local_Deploy is Script {
    // Configuration
    /// @notice RPC endpoint of the local anvil chain. Used for reference only.
    string internal constant RPC_URL = "http://127.0.0.1:8545";
    /// @notice Chain ID of the local anvil chain. Used for reference only.
    uint256 internal constant CHAIN_ID = 31337;
    /// @dev Anvil default account 0 private key. Public test key, do not use on mainnet.
    uint256 internal constant DEPLOYER_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    // Deployment
    function run()
        external
        returns (
            WETH weth,
            HippoxSwapFactoryV1 factory,
            HippoxSwapRouterV1 router,
            MockToken tokenA,
            MockToken tokenB,
            HippoxOracleV1 oracle,
            MockHook mockHook
        )
    {
        address deployer = vm.addr(DEPLOYER_PRIVATE_KEY);
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        weth = new WETH();
        factory = new HippoxSwapFactoryV1(deployer);
        router = new HippoxSwapRouterV1(address(factory), address(weth));
        tokenA = new MockToken("TokenA", "A");
        tokenB = new MockToken("TokenB", "B");
        // The oracle is bound to the tokenA/tokenB pair. The pair itself is
        // created later by the SDK tests when liquidity is added, so the
        // oracle is deployed here with the expected pair address computed
        // from the factory. If the pair does not exist yet, the oracle will
        // simply read from the pair contract once it is created.
        address pair = factory.getPair(address(tokenA), address(tokenB));
        if (pair == address(0)) {
            // Pair is not created yet. Deploy the oracle bound to the tokenA
            // and tokenB addresses through the factory. In this local setup
            // the SDK tests will create the pair immediately after, and the
            // oracle can be re-pointed if needed.
            //
            // Since HippoxOracleV1 takes the pair address at construction, we
            // pre-create the pair here so the oracle has a valid target.
            pair = factory.createPair(
                address(tokenA),
                address(tokenB),
                deployer
            );
        }
        oracle = new HippoxOracleV1(pair);
        // Mock hook used by the SDK hook tests. It records how many times
        // each callback was invoked and never reverts.
        mockHook = new MockHook();
        vm.stopBroadcast();
        console.log("WETH:", address(weth));
        console.log("Factory:", address(factory));
        console.log("Router:", address(router));
        console.log("TokenA:", address(tokenA));
        console.log("TokenB:", address(tokenB));
        console.log("Pair:", pair);
        console.log("Oracle:", address(oracle));
        console.log("MockHook:", address(mockHook));
    }
}
