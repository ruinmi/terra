// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {TerraStableCoin} from "src/TerraStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";
/**
 * @dev The system have the tokens maintain a 1 token == $1 peg.
 * This contract is the core of the TSC System. It handles all the logic for mining
 * and redeeming TSC, as well as depositing & withdrawing collateral.
 *
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmic Stable
 *
 * This mocks Terra/Moon, but uses exogenous collateral.
 *
 */
contract TerraEngine is ReentrancyGuard {
    //////////////////////////
    //        Errors        //
    //////////////////////////
    
    error TerraEngine_LengthNotEqual();
    error TerraEngine_TokenNotSupported();
    error TerraEngine_MustGreaterThanZero();
    error TerraEngine_TransferFailed();
    error TerraEngine_CollateralLow();
    error TerraEngine_MintFailed();
    error TerraEngine_RedeemAmountExceeded();
    error TerraEngine_BurnAmountExceeded();
    error TerraEngine_HealthFactorNotImproved();

    //////////////////////
    //      Types       //
    //////////////////////
    
    using OracleLib for AggregatorV3Interface;

    ///////////////////////////
    //      State Vars       //
    ///////////////////////////
    
    uint256 private constant LIQUIDATION_THRESHOLD = 200; // means 200% over collateralized
    uint256 private constant LIQUIDATION_DECIMALS = 2;
    uint256 private constant BONUS_NUMERATOR = 10; // liquidator gets 10% of the debt they covered
    uint256 private constant BONUS_DENOMINATOR = 100;

    // Stores collateral amounts for each user per token
    mapping(address user => mapping(address tokenAddr => uint256 amount)) private _collateralStore;
    // Tracks amount of TSC minted by each user
    mapping(address user => uint256 amount) private _tscMinted;
    // Maps collateral token address to Chainlink price feed address
    mapping(address tokenAddr => address dataFeed) private _dataFeeds;
    // List of supported collateral token addresses
    address[] private _collateralTokenAddresses;

    // Reference to the TerraStableCoin contract
    TerraStableCoin private immutable _tsc;

    //////////////////////////
    //        Events        //
    //////////////////////////
    
    event CollateralDeposited(address indexed user, address indexed tokenAddr, uint256 amount);
    event TSCMinted(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed tokenAddr, uint256 amount);
    event TSCBurned(address indexed behalfOf, address indexed from, uint256 amount);

    //////////////////////////
    //       Modifiers      //
    //////////////////////////
    
    modifier moreThanZero(uint256 value) {
        require(value > 0, TerraEngine_MustGreaterThanZero());
        _;
    }

    modifier tokenAddressSupported(address tokenAddress) {
        require(_dataFeeds[tokenAddress] != address(0), TerraEngine_TokenNotSupported());
        _;
    }

    ////////////////////////////
    //       Constructor      //
    ////////////////////////////

    /**
     * @param terraStableCoin Address of the TSC token contract
     * @param tokenAddresses List of collateral token addresses
     * @param dataFeeds Corresponding Chainlink data feed addresses for each token
     */
    constructor(address terraStableCoin, address[] memory tokenAddresses, address[] memory dataFeeds) {
        require(tokenAddresses.length == dataFeeds.length, TerraEngine_LengthNotEqual());

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            _dataFeeds[tokenAddresses[i]] = dataFeeds[i];
            _collateralTokenAddresses.push(tokenAddresses[i]);
        }
        _tsc = TerraStableCoin(terraStableCoin);
    }
    
    //////////////////////////////
    //        Functions         //
    //////////////////////////////

    /**
     * @dev deposit collateral and mint TSC in one transaction.
     * @param tokenAddr The address of the token to deposit as collateral.
     * @param collateralAmount The amount of the token to deposit as collateral.
     * @param tscAmount The amount of TSC to mint.
     */
    function depositCollateralAndMintTSC(address tokenAddr, uint256 collateralAmount, uint256 tscAmount)
        external
        tokenAddressSupported(tokenAddr)
    {
        depositCollateral(tokenAddr, collateralAmount);
        mintTSC(tscAmount);
    }

    /**
     * @dev deposit collateral to this contract.
     * @param tokenAddr The address of the token to deposit as collateral.
     * @param collateralAmount The amount of the token to deposit as collateral.
     */
    function depositCollateral(address tokenAddr, uint256 collateralAmount)
        public
        nonReentrant
        tokenAddressSupported(tokenAddr)
        moreThanZero(collateralAmount)
    {
        emit CollateralDeposited(msg.sender, tokenAddr, collateralAmount);
        _collateralStore[msg.sender][tokenAddr] += collateralAmount;

        bool success = IERC20(tokenAddr).transferFrom(msg.sender, address(this), collateralAmount);
        require(success, TerraEngine_TransferFailed());
    }

    /**
     * @dev mint Terra Stable Coin (TSC) for the user.
     * This function checks the user's health factor to ensure it is above the liquidation threshold.
     * @param amountTSC The amount of TSC to mint for the user.
     * This function will revert if the health factor is below the liquidation threshold.
     * It will also revert if the amount to mint is zero.
     * Emits a TSCMinted event on success.
     */
    function mintTSC(uint256 amountTSC) public nonReentrant moreThanZero(amountTSC) {
        emit TSCMinted(msg.sender, amountTSC);
        _tscMinted[msg.sender] += amountTSC;
        _revertIfHealthFactorBroken(msg.sender);

        bool minted = _tsc.mint(msg.sender, amountTSC);

        require(minted, TerraEngine_MintFailed());
    }

    /**
     * @dev Burns TSC and redeems collateral in a single transaction.
     * @param tokenAddress Address of the collateral token to redeem.
     * @param collateralAmount Amount of collateral to redeem.
     * @param tscAmount Amount of TSC to burn.
     */
    function redeemCollateralByRepayingTSC(address tokenAddress, uint256 collateralAmount, uint256 tscAmount)
        external
        tokenAddressSupported(tokenAddress)
    {
        burnTSC(tscAmount);
        redeemCollateral(tokenAddress, collateralAmount);
    }

    /**
     * @dev Redeems collateral for the caller.
     * @param tokenAddress Address of the collateral token to redeem.
     * @param collateralAmount Amount of collateral to redeem.
     */
    function redeemCollateral(address tokenAddress, uint256 collateralAmount)
        public
        tokenAddressSupported(tokenAddress)
    {
        _redeemCollateral(msg.sender, msg.sender, tokenAddress, collateralAmount);
    }

    /**
     * @dev Burns TSC from the caller's account.
     * @param amount Amount of TSC to burn.
     */
    function burnTSC(uint256 amount) public moreThanZero(amount) {
        _burnTSC(msg.sender, msg.sender, amount);
    }

    /**
     * @dev Liquidates part of a user's debt if their position is undercollateralized.
     * The liquidator covers a portion of the user's debt in exchange for collateral plus a bonus.
     * @param tokenAddress Address of the collateral token to seize.
     * @param user Address of the user being liquidated.
     * @param tscAmountCovered Amount of TSC debt the liquidator is repaying.
     */
    function liquidate(address tokenAddress, address user, uint256 tscAmountCovered)
        external
        tokenAddressSupported(tokenAddress)
    {
        // collateral $100ETH,  debt 60
        // liquidator pay debt 50, get collateral $55ETH
        // collateral $45ETH, debt 10
        uint256 startingHealthFactor = _getHealthFactor(user);

        _burnTSC(user, msg.sender, tscAmountCovered);

        uint256 bonus = tscAmountCovered * BONUS_NUMERATOR / BONUS_DENOMINATOR;
        uint256 redeemAmount = getTokenAmountFromUSD(tokenAddress, tscAmountCovered + bonus);
        _redeemCollateral(user, msg.sender, tokenAddress, redeemAmount);

        uint256 afterHealthFactor = _getHealthFactor(user);
        require(startingHealthFactor < afterHealthFactor, TerraEngine_HealthFactorNotImproved());
        _revertIfHealthFactorBroken(msg.sender);
    }

    //////////////////////////////////
    //      Private Functions       //
    //////////////////////////////////
    
    /**
     * @dev Reverts if the user's health factor is below the liquidation threshold.
     */
    function _revertIfHealthFactorBroken(address user) private view {
        uint256 factor = _getHealthFactor(user);
        require(factor >= LIQUIDATION_THRESHOLD, TerraEngine_CollateralLow());
    }

    /**
     * @dev Redeems collateral from `from` to `to`.
     * Updates state and performs token transfer.
     */
    function _redeemCollateral(address from, address to, address tokenAddress, uint256 collateralAmount)
        private
        nonReentrant
        tokenAddressSupported(tokenAddress)
        moreThanZero(collateralAmount)
    {
        // check
        require(collateralAmount <= _collateralStore[from][tokenAddress], TerraEngine_RedeemAmountExceeded());

        // Effects
        emit CollateralRedeemed(from, to, tokenAddress, collateralAmount);
        _collateralStore[from][tokenAddress] -= collateralAmount;
        _revertIfHealthFactorBroken(from);

        // interactions
        IERC20(tokenAddress).transfer(to, collateralAmount);
    }

    /**
     * @dev Burns TSC on behalf of `behalfOf` using tokens from `from`.
     * Updates minted amount and calls burn on TSC contract.
     */
    function _burnTSC(address behalfOf, address from, uint256 amount) private nonReentrant moreThanZero(amount) {
        require(amount <= _tscMinted[behalfOf], TerraEngine_BurnAmountExceeded());
        
        emit TSCBurned(behalfOf, from, amount);
        _tscMinted[behalfOf] -= amount;
        _revertIfHealthFactorBroken(behalfOf);

        _tsc.transferFrom(from, address(this), amount);
        _tsc.burn(amount);
    }

    /**
     * @dev Get the health factor of the user.
     * The health factor is calculated as the total collateral value in USD divided by the amount of TSC minted.
     * A health factor below 200 means the user is at risk of liquidation.
     * The health factor is returned as a percentage with 2 decimal places (e.g., 300 means 3.00).
     */
    function _getHealthFactor(address user) private view returns (uint256) {
        uint256 debt = _tscMinted[user];
        if (debt == 0) return type(uint256).max;

        uint256 totalCollateralValueInUSD = _getCollateralValueInUSD(user);

        return totalCollateralValueInUSD * 10 ** LIQUIDATION_DECIMALS / debt;
    }

    /**
     * @dev Get the total collateral value in USD for the user.
     * This function iterates over all collateral tokens and calculates their value in USD.
     * The total value is returned as a uint256.
     */
    function _getCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < _collateralTokenAddresses.length; i++) {
            address tokenAddress = _collateralTokenAddresses[i];
            uint256 amountCollateral = _collateralStore[user][tokenAddress];
            uint256 valueCollateral = getUSDValue(tokenAddress, amountCollateral);
            totalCollateralValueInUSD += valueCollateral;
        }
        return totalCollateralValueInUSD;
    }

    ////////////////////////////////////////////////
    //        Public View & Pure Functions        //
    ////////////////////////////////////////////////

    function getHealthFactor() public view returns (uint256) {
        return _getHealthFactor(msg.sender);
    }

    function getCollateralValueInUSD() public view returns (uint256 totalCollateralValueInUSD) {
        return _getCollateralValueInUSD(msg.sender);
    }

    function getCollateralAmount(address token)
        public
        view
        tokenAddressSupported(token)
        returns (uint256 totalCollateralAmount)
    {
        return _collateralStore[msg.sender][token];
    }

    function getUSDValue(address token, uint256 amount) public view tokenAddressSupported(token) returns (uint256) {
        (, int256 answer,,,) = AggregatorV3Interface(_dataFeeds[token]).staleCheckLatestRoundData();
        return uint256(answer) * amount / 1e8;
    }

    function getTokenAmountFromUSD(address token, uint256 usd)
        public
        view
        tokenAddressSupported(token)
        returns (uint256)
    {
        (, int256 answer,,,) = AggregatorV3Interface(_dataFeeds[token]).staleCheckLatestRoundData();
        // $30e18 / $2000e8/ETH * 1e8
        return usd * 1e8 / uint256(answer);
    }

    function getTSCMinted(address user) external view returns (uint256) {
        return _tscMinted[user];
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationDecimals() external pure returns (uint256) {
        return LIQUIDATION_DECIMALS;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return BONUS_DENOMINATOR / BONUS_DENOMINATOR;
    }

    function getTerraStableCoin() external view returns (address) {
        return address(_tsc);
    }
}
