// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";
import {TerraStableCoin} from "src/TerraStableCoin.sol";
import {TerraEngine} from "src/TerraEngine.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

/**
 * @dev Provides network-specific deployment configurations for the TerraEngine system.
 * Used during Forge script execution to deploy mock tokens and price feeds locally
 * or to return existing addresses on live testnets.
 */
contract ConfigProvider is Script {
    error ConfigProvider_ChainIdNotSupported();

    uint8 private constant DECIMALS = 8;
    int256 private constant WBTC_PRICE = 100000 * 1e8;
    int256 private constant WETH_PRICE = 4000 * 1e8;
    address private constant ANVIL_USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    struct DeployConfig {
        uint8 wbtcIndex;
        uint8 wethIndex;
        address[] tokenAddresses;
        address[] priceFeeds;
    }

    /**
     * @dev Returns a deployment config depending on the current network's chain ID.
     * Supports:
     * - 31337: Anvil local network (deploys mocks)
     * - 11155111: Sepolia testnet (uses pre-deployed contracts)
     */
    function getConfig() public returns (DeployConfig memory) {
        if (block.chainid == 31337) {
            return _getAnvilConfig();
        } else if (block.chainid == 11155111) {
            return _getSepoliaConfig();
        } else {
            revert ConfigProvider_ChainIdNotSupported();
        }
    }

    function _getAnvilConfig() private returns (DeployConfig memory) {
        vm.startBroadcast();
        ERC20Mock wbtc = new ERC20Mock("WBTC", "WBTC", ANVIL_USER, 1000e8);
        MockV3Aggregator priceFeedWBTC = new MockV3Aggregator(DECIMALS, WBTC_PRICE);

        ERC20Mock weth = new ERC20Mock("WETH", "WETH", ANVIL_USER, 1000e8);
        MockV3Aggregator priceFeedWETH = new MockV3Aggregator(DECIMALS, WETH_PRICE);
        vm.stopBroadcast();

        DeployConfig memory config =
            DeployConfig({wbtcIndex: 0, wethIndex: 1, tokenAddresses: new address[](2), priceFeeds: new address[](2)});
        // WBTC
        config.tokenAddresses[config.wbtcIndex] = address(wbtc);
        config.priceFeeds[config.wbtcIndex] = address(priceFeedWBTC);

        // WETH
        config.tokenAddresses[config.wethIndex] = address(weth);
        config.priceFeeds[config.wethIndex] = address(priceFeedWETH);

        return config;
    }

    function _getSepoliaConfig() private pure returns (DeployConfig memory) {
        DeployConfig memory config =
            DeployConfig({wbtcIndex: 0, wethIndex: 1, tokenAddresses: new address[](2), priceFeeds: new address[](2)});
        // WBTC
        config.tokenAddresses[config.wbtcIndex] = 0x29f2D40B0605204364af54EC677bD022dA425d03;
        config.priceFeeds[config.wbtcIndex] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

        // WETH
        config.tokenAddresses[config.wethIndex] = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        config.priceFeeds[config.wethIndex] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

        return config;
    }
}
