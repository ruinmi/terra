// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev This contract meant to be governed by TerraEngine.
 * This contract is the ERC20 implementation of our stablecoin system.
 *
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 */
contract TerraStableCoin is ERC20Burnable, Ownable {
    error TerraStableCoin_ValueNotGreaterThanZero();
    error TerraStableCoin_AddressIsZero();
    error TerraStableCoin_BalanceInsufficient();

    constructor() ERC20("TerraStableCoin", "TSC") Ownable(msg.sender) {}

    function burn(uint256 value) public virtual override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        require(balance >= value, TerraStableCoin_BalanceInsufficient());

        super.burn(value);
    }

    function mint(address account, uint256 value) external onlyOwner returns (bool) {
        require(account != address(0), TerraStableCoin_AddressIsZero());
        require(value > 0, TerraStableCoin_ValueNotGreaterThanZero());

        _mint(account, value);
        return true;
    }
}
