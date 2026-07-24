// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockERC20
/// @notice Testnet-only token with public mint function
contract MockERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Anyone can mint testnet tokens
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Faucet: mint 1000 tokens to caller
    function faucet() external {
        _mint(msg.sender, 1000 * (10 ** _decimals));
    }
}
