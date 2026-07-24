// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title USDAxToken
/// @notice The USDAX stablecoin. Only the VaultEngine can mint or burn.
contract USDAxToken is ERC20, ERC20Permit, Ownable {
    address public vaultEngine;

    event VaultEngineSet(address indexed engine);

    modifier onlyVaultEngine() {
        require(msg.sender == vaultEngine, "USDax: not vault engine");
        _;
    }

    constructor(address owner_) ERC20("USDAX Stablecoin", "USDAX") ERC20Permit("USDAX Stablecoin") Ownable(owner_) {}

    /// @notice Set the VaultEngine address (owner only, one-time — cannot be changed once set)
    function setVaultEngine(address engine) external onlyOwner {
        require(engine != address(0), "zero address");
        require(vaultEngine == address(0), "engine already set");
        vaultEngine = engine;
        emit VaultEngineSet(engine);
    }

    /// @notice Mint USDAX — only VaultEngine
    function mint(address to, uint256 amount) external onlyVaultEngine {
        _mint(to, amount);
    }

    /// @notice Burn USDAX — only VaultEngine
    function burn(address from, uint256 amount) external onlyVaultEngine {
        _burn(from, amount);
    }
}
