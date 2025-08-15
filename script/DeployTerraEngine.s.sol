// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script, console} from "forge-std/Script.sol";
import {TerraStableCoin} from "src/TerraStableCoin.sol";
import {TerraEngine} from "src/TerraEngine.sol";
import {ConfigProvider} from "script/ConfigProvider.s.sol";

contract DeployTerraEngine is Script {
    function run() external returns (TerraStableCoin, TerraEngine, ConfigProvider.DeployConfig memory) {
        ConfigProvider configProvider = new ConfigProvider();
        ConfigProvider.DeployConfig memory config = configProvider.getConfig();

        vm.startBroadcast();
        TerraStableCoin tsc = new TerraStableCoin();
        TerraEngine terraEngine = new TerraEngine(address(tsc), config.tokenAddresses, config.priceFeeds);
        tsc.transferOwnership(address(terraEngine));
        vm.stopBroadcast();

        return (tsc, terraEngine, config);
    }
}
