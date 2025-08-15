// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {TerraEngine} from "src/TerraEngine.sol";
import {ConfigProvider} from "script/ConfigProvider.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {TerraStableCoin} from "src/TerraStableCoin.sol";

contract StopOnRevertHandler is Test {
    TerraEngine public terraEngine;
    TerraStableCoin public tsc;
    ConfigProvider.DeployConfig public config;

    uint256 public AMOUNT_MAX_DEPOSIT = type(uint96).max;
    address[] public USER_DEPOSITED;

    uint256 public timesMintIsCalled;

    constructor(TerraEngine te, TerraStableCoin _tsc, ConfigProvider.DeployConfig memory c) {
        terraEngine = te;
        config = c;
        tsc = _tsc;
    }

    function depositCollateral(uint256 tokenAddressSeed, uint256 collateralAmount) public {
        address tokenAddress = _getTokenAddress(tokenAddressSeed);
        _mintAndApprove(tokenAddress);
        collateralAmount = bound(collateralAmount, 1, AMOUNT_MAX_DEPOSIT);
        vm.prank(msg.sender);
        terraEngine.depositCollateral(tokenAddress, collateralAmount);
        USER_DEPOSITED.push(msg.sender);
    }

    function redeemCollateral(uint256 tokenAddressSeed, uint256 collateralAmount) public {
        address tokenAddress = _getTokenAddress(tokenAddressSeed);
        vm.prank(msg.sender);
        uint256 collateralInUSD = terraEngine.getCollateralValueInUSD();
        vm.prank(msg.sender);
        uint256 amountToken = terraEngine.getCollateralAmount(tokenAddress);
        vm.assume(collateralAmount > 0);
        vm.assume(collateralAmount <= amountToken);
        uint256 usdToRedeem = terraEngine.getUSDValue(tokenAddress, collateralAmount);
        uint256 tscMinted = terraEngine.getTSCMinted(msg.sender);

        vm.assume((collateralInUSD - usdToRedeem) / 2 >= tscMinted);

        vm.prank(msg.sender);
        terraEngine.redeemCollateral(tokenAddress, collateralAmount);
    }

    function mintTSC(uint256 senderSeed, uint256 amountTSC) public {
        vm.assume(USER_DEPOSITED.length > 0);
        address sender = _getUser(senderSeed);
        vm.prank(sender);
        uint256 collateralInUSD = terraEngine.getCollateralValueInUSD();
        uint256 tscMinted = terraEngine.getTSCMinted(sender);
        vm.assume(amountTSC > 0);
        uint256 maxTSCToMint = collateralInUSD / 2 - tscMinted;
        vm.assume(maxTSCToMint > 0);
        amountTSC = bound(amountTSC, 1, maxTSCToMint);

        vm.prank(sender);
        terraEngine.mintTSC(amountTSC);
        timesMintIsCalled++;
    }

    //    // collateral token plummet!!
    //    function updatePriceFeedResult(uint96 price) public {
    //        MockV3Aggregator dataFeed = MockV3Aggregator(config.priceFeeds[config.wethIndex]);
    //        dataFeed.updateAnswer(int256(uint256(price)));
    //    }

    // amountCovered must greater than some value (can't be too small)
//    function liquidate(uint256 tokenAddressSeed, uint256 userSeed, uint256 amountCovered) public {
//        vm.assume(USER_DEPOSITED.length > 0);
//        address user = _getUser(userSeed);
////        vm.prank(user);
////        vm.assume(terraEngine.getHealthFactor() >= 200);
//        address tokenAddress = _getTokenAddress(tokenAddressSeed);
//        uint256 amountMinted = terraEngine.getTSCMinted(user);
//        vm.assume(amountMinted > 0);
//        amountCovered = bound(amountCovered, 1, amountMinted);
//
//
//        vm.prank(address(terraEngine));
//        bool mint = tsc.mint(msg.sender, amountCovered);
//        
//        vm.startPrank(msg.sender);
//        tsc.approve(address(terraEngine), amountCovered);
//        terraEngine.liquidate(tokenAddress, user, amountCovered);
//        vm.stopPrank();
//
//    }

    function _getUser(uint256 seed) private view returns (address) {
        return USER_DEPOSITED[seed % USER_DEPOSITED.length];
    }

    function _getTokenAddress(uint256 seed) private view returns (address) {
        address tokenAddress = config.tokenAddresses[seed % 2];
        return tokenAddress;
    }

    function _mintAndApprove(address tokenAddress) private {
        ERC20Mock token = ERC20Mock(tokenAddress);
        token.mint(msg.sender, AMOUNT_MAX_DEPOSIT);
        vm.prank(msg.sender);
        token.approve(address(terraEngine), AMOUNT_MAX_DEPOSIT);
    }
}
