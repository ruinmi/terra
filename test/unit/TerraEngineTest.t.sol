// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test, console} from "forge-std/Test.sol";
import {TerraEngine} from "src/TerraEngine.sol";
import {TerraStableCoin} from "src/TerraStableCoin.sol";
import {DeployTerraEngine} from "script/DeployTerraEngine.s.sol";
import {ConfigProvider} from "script/ConfigProvider.s.sol";
import {ERC20Mock} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TerraEngineTest is Test {
    TerraStableCoin public tsc;
    TerraEngine public terraEngine;
    ConfigProvider.DeployConfig public config;

    address public USER = makeAddr("user");
    address public ME = makeAddr("me");
    address public wbtcAddress;
    address public wethAddress;

    uint256 public constant AMOUNT_ERC20_BALANCE = 100 ether;
    uint256 public constant AMOUNT_DEPOSIT_TOKEN = 10 ether;
    uint256 public constant AMOUNT_DEPOSIT_TSC_GET = 4000 ether;
    uint256 public constant AMOUNT_DEPOSIT_TSC_GET_OVERMUCH = 500_000 ether;
    uint256 public constant AMOUNT_REDEEMED_TOKEN = 9 ether; // $2000 TSC Burn Needed
    uint256 public constant AMOUNT_REDEEMED_TSC_BURNED = 2000 ether;
    uint256 public constant AMOUNT_COVERED_TSC = 10 ether;

    function setUp() external {
        DeployTerraEngine deploy = new DeployTerraEngine();
        (tsc, terraEngine, config) = deploy.run();
        wbtcAddress = config.tokenAddresses[config.wbtcIndex];
        wethAddress = config.tokenAddresses[config.wethIndex];

        ERC20Mock(wethAddress).mint(USER, AMOUNT_ERC20_BALANCE);
        ERC20Mock(wbtcAddress).mint(USER, AMOUNT_ERC20_BALANCE);
        ERC20Mock(wethAddress).mint(ME, AMOUNT_ERC20_BALANCE);
        ERC20Mock(wbtcAddress).mint(ME, AMOUNT_ERC20_BALANCE);
        vm.startPrank(USER);
        IERC20(wethAddress).approve(address(terraEngine), AMOUNT_DEPOSIT_TOKEN);
        IERC20(wbtcAddress).approve(address(terraEngine), AMOUNT_DEPOSIT_TOKEN);
        vm.stopPrank();
        vm.startPrank(ME);
        IERC20(wethAddress).approve(address(terraEngine), AMOUNT_DEPOSIT_TOKEN);
        IERC20(wbtcAddress).approve(address(terraEngine), AMOUNT_DEPOSIT_TOKEN);
        vm.stopPrank();
    }

    modifier depositAndMint() {
        vm.prank(USER);
        terraEngine.depositCollateralAndMintTSC(wethAddress, AMOUNT_DEPOSIT_TOKEN, AMOUNT_DEPOSIT_TSC_GET);
        _;
    }

    /////////////////////////////
    //        Price Tests       //
    /////////////////////////////
    function test_getUSDValue() external view {
        uint256 usd = terraEngine.getUSDValue(wethAddress, 35 ether);
        // 35e18 * $4000/ETH = 140000e18
        assert(usd == 140000e18);
    }

    function test_getCollateralValueInUSD() external depositAndMint {
        vm.prank(USER);
        uint256 usd = terraEngine.getCollateralValueInUSD();

        assert(usd == AMOUNT_DEPOSIT_TOKEN * 4000);
    }

    ///////////////////////////////////
    //     depositCollateral Tests   //
    ///////////////////////////////////
    function test_depositCollateral() external {
        vm.prank(USER);
        terraEngine.depositCollateral(wethAddress, AMOUNT_DEPOSIT_TOKEN);
    }

    function test_depositCollateralFailedIfZero() external {
        vm.prank(USER);
        vm.expectRevert(TerraEngine.TerraEngine_MustGreaterThanZero.selector);
        terraEngine.depositCollateral(wethAddress, 0);
    }

    function test_depositCollateralFailedIfWrongToken() external {
        vm.prank(USER);
        vm.expectRevert(TerraEngine.TerraEngine_TokenNotSupported.selector);
        // 5.12 * 8.31
        // 0101. * 1000
        terraEngine.depositCollateral(address(0), AMOUNT_DEPOSIT_TOKEN);
    }

    //////////////////////////
    //     mintTSC Tests   //
    /////////////////////////
    function test_mintTSCFailedIfMintTooMuch() external {
        vm.startPrank(USER);
        terraEngine.depositCollateral(wethAddress, AMOUNT_DEPOSIT_TOKEN);

        vm.expectRevert(TerraEngine.TerraEngine_CollateralLow.selector);
        terraEngine.mintTSC(AMOUNT_DEPOSIT_TSC_GET_OVERMUCH);
        vm.stopPrank();
    }

    function test_mintTSCFailedIfAmountZero() external {
        vm.startPrank(USER);
        terraEngine.depositCollateral(wethAddress, AMOUNT_DEPOSIT_TOKEN);

        vm.expectRevert(TerraEngine.TerraEngine_MustGreaterThanZero.selector);
        terraEngine.mintTSC(0);
        vm.stopPrank();
    }

    ////////////////////////////////////
    //        getHealthFactor         //
    ////////////////////////////////////
    function test_getHealthFactor() external {
        vm.startPrank(USER);
        terraEngine.depositCollateral(wethAddress, AMOUNT_DEPOSIT_TOKEN);
        uint256 collateralInUSD = terraEngine.getCollateralValueInUSD();
        terraEngine.mintTSC(collateralInUSD / 3);

        // collateralInUSD / (collateralInUSD / 3) * 100 = 300
        uint256 factor = terraEngine.getHealthFactor();
        assert(factor == 300);
    }

    ////////////////////////////
    //        burnTSC         //
    ////////////////////////////
    function test_burnTSC() external depositAndMint {
        uint256 amountBurned = AMOUNT_DEPOSIT_TSC_GET / 2;
        vm.startPrank(USER);
        tsc.approve(address(terraEngine), amountBurned);
        terraEngine.burnTSC(amountBurned);
        vm.stopPrank();

        assert(terraEngine.getTSCMinted(USER) == AMOUNT_DEPOSIT_TSC_GET / 2);
    }

    function test_burnTSCFailedIfAmountExceeded() external depositAndMint {
        uint256 amountBurned = AMOUNT_DEPOSIT_TSC_GET + 2;
        vm.startPrank(USER);
        tsc.approve(address(terraEngine), amountBurned);
        vm.expectRevert(TerraEngine.TerraEngine_BurnAmountExceeded.selector);
        terraEngine.burnTSC(amountBurned);
        vm.stopPrank();
    }

    function test_burnTSCFailedIfAmountZero() external depositAndMint {
        uint256 amountBurned = AMOUNT_DEPOSIT_TSC_GET / 2;
        vm.startPrank(USER);
        tsc.approve(address(terraEngine), amountBurned);

        vm.expectRevert(TerraEngine.TerraEngine_MustGreaterThanZero.selector);
        terraEngine.burnTSC(0);
        vm.stopPrank();
    }

    ////////////////////////////////////
    //        redeemCollateral        //
    ////////////////////////////////////
    function test_redeemCollateral() external depositAndMint {
        vm.startPrank(USER);
        uint256 startingCollateral = terraEngine.getCollateralValueInUSD();

        terraEngine.redeemCollateral(wethAddress, AMOUNT_DEPOSIT_TOKEN / 5);

        uint256 endingCollateral = terraEngine.getCollateralValueInUSD();
        vm.stopPrank();

        assert(startingCollateral * 4 / 5 == endingCollateral);
    }

    function test_redeemCollateralFailedIfAmountExceeded() external depositAndMint {
        vm.prank(USER);
        vm.expectRevert(TerraEngine.TerraEngine_RedeemAmountExceeded.selector);
        terraEngine.redeemCollateral(wethAddress, AMOUNT_DEPOSIT_TOKEN + 1);
    }

    function test_redeemCollateralFailedIfAmountZero() external depositAndMint {
        vm.startPrank(USER);
        vm.expectRevert(TerraEngine.TerraEngine_MustGreaterThanZero.selector);
        terraEngine.redeemCollateral(wethAddress, 0);
        vm.stopPrank();
    }

    //////////////////////////////////////////////////
    //        redeemCollateralByRepayingTSC         //
    //////////////////////////////////////////////////
    function test_redeemCollateralByRepayingTSC() external depositAndMint {
        vm.startPrank(USER);
        uint256 startingTSCAmount = tsc.balanceOf(USER);
        uint256 startingTokenAmount = IERC20(wethAddress).balanceOf(USER);
        uint256 startingDebt = terraEngine.getTSCMinted(USER);
        uint256 startingTokenDeposited = terraEngine.getCollateralAmount(wethAddress);

        tsc.approve(address(terraEngine), AMOUNT_REDEEMED_TSC_BURNED);
        terraEngine.redeemCollateralByRepayingTSC(wethAddress, AMOUNT_REDEEMED_TOKEN, AMOUNT_REDEEMED_TSC_BURNED);

        uint256 endingTSCAmount = tsc.balanceOf(USER);
        uint256 endingTokenAmount = IERC20(wethAddress).balanceOf(USER);
        uint256 endingDebt = terraEngine.getTSCMinted(USER);
        uint256 endingTokenDeposited = terraEngine.getCollateralAmount(wethAddress);
        vm.stopPrank();

        assert(startingTSCAmount - AMOUNT_REDEEMED_TSC_BURNED == endingTSCAmount);
        assert(startingTokenAmount + AMOUNT_REDEEMED_TOKEN == endingTokenAmount);
        assert(startingDebt - AMOUNT_REDEEMED_TSC_BURNED == endingDebt);
        assert(startingTokenDeposited - AMOUNT_REDEEMED_TOKEN == endingTokenDeposited);
    }

    //////////////////////////////
    //        liquidate         //
    //////////////////////////////
    function test_liquidate() external depositAndMint {
        // Arrange
        vm.prank(ME);
        terraEngine.depositCollateralAndMintTSC(wethAddress, AMOUNT_DEPOSIT_TOKEN, AMOUNT_DEPOSIT_TSC_GET);
        uint256 startingWETHBalanceMe = IERC20(wethAddress).balanceOf(ME);
        uint256 startingTSCBalanceMe = tsc.balanceOf(ME);
        vm.startPrank(USER);
        uint256 startingCollateralBalanceUser = terraEngine.getCollateralAmount(wethAddress);
        uint256 startingTSCMintedUser = terraEngine.getTSCMinted(USER);
        vm.stopPrank();

        // Act
        vm.startPrank(ME);
        tsc.approve(address(terraEngine), AMOUNT_COVERED_TSC);
        terraEngine.liquidate(wethAddress, USER, AMOUNT_COVERED_TSC);
        vm.stopPrank();

        vm.startPrank(USER);
        uint256 endingCollateralBalanceUser = terraEngine.getCollateralAmount(wethAddress);
        uint256 endingTSCMintedUser = terraEngine.getTSCMinted(USER);
        vm.stopPrank();

        uint256 endingWETHBalanceMe = IERC20(wethAddress).balanceOf(ME);
        uint256 endingTSCBalanceMe = tsc.balanceOf(ME);

        // Assert
        uint256 bonusWETHAmount = terraEngine.getTokenAmountFromUSD(wethAddress, AMOUNT_COVERED_TSC * 110 / 100);
        assert(startingWETHBalanceMe + bonusWETHAmount == endingWETHBalanceMe);
        assert(startingCollateralBalanceUser - bonusWETHAmount == endingCollateralBalanceUser);
        assert(startingTSCBalanceMe - AMOUNT_COVERED_TSC == endingTSCBalanceMe);
        assert(startingTSCMintedUser - AMOUNT_COVERED_TSC == endingTSCMintedUser);
    }

    function test_liquidateFailedIfAmountZero() external depositAndMint {
        vm.prank(ME);
        terraEngine.depositCollateralAndMintTSC(wethAddress, AMOUNT_DEPOSIT_TOKEN, AMOUNT_DEPOSIT_TSC_GET);

        vm.startPrank(ME);
        tsc.approve(address(terraEngine), AMOUNT_COVERED_TSC);
        vm.expectRevert(TerraEngine.TerraEngine_MustGreaterThanZero.selector);
        terraEngine.liquidate(wethAddress, USER, 0);
        vm.stopPrank();

        // 30  20
        // 28.9  19
    }
}
