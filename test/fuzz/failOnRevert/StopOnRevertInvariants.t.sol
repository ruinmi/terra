// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployTerraEngine} from "script/DeployTerraEngine.s.sol";
import {TerraStableCoin} from "src/TerraStableCoin.sol";
import {TerraEngine} from "src/TerraEngine.sol";
import {ConfigProvider} from "script/ConfigProvider.s.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {StopOnRevertHandler} from "test/fuzz/failOnRevert/StopOnRevertHandler.sol";

contract StopOnRevertInvariants is Test {
    TerraStableCoin public tsc;
    TerraEngine public terraEngine;
    ConfigProvider.DeployConfig public config;
    StopOnRevertHandler public handler;
    
    address public wethAddress;
    address public wbtcAddress;

    function setUp() external {
        DeployTerraEngine deployer = new DeployTerraEngine();
        (tsc, terraEngine, config) = deployer.run();
        handler = new StopOnRevertHandler(terraEngine, tsc, config);

        wethAddress = config.tokenAddresses[config.wethIndex];
        wbtcAddress = config.tokenAddresses[config.wbtcIndex];

        targetContract(address(handler));
    }

    function invariant_collateralNeverLessThanTSC() external view {
        uint256 collateralTotalInUSD = terraEngine.getUSDValue(
            wethAddress, ERC20Mock(wethAddress).balanceOf(address(terraEngine))
        ) + terraEngine.getUSDValue(wbtcAddress, ERC20Mock(wbtcAddress).balanceOf(address(terraEngine)));
        uint256 TSCTotal = tsc.totalSupply();
        
        console.log("total collateral:", collateralTotalInUSD);
        console.log("total supply    :", TSCTotal);
        console.log("mint is being called:", handler.timesMintIsCalled());

        assert(collateralTotalInUSD >= TSCTotal);
    }

    function invariant_gettersNeverRevert() external view {
        terraEngine.getLiquidationBonus();
        terraEngine.getLiquidationDecimals();
        terraEngine.getLiquidationThreshold();
        terraEngine.getTerraStableCoin();
    }
}
