// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CollateralManager
/// @notice Stores risk parameters for each whitelisted collateral token
contract CollateralManager is Ownable {
    uint256 public constant BASIS_POINTS = 10_000;

    struct CollateralConfig {
        bool     enabled;
        uint256  maxLTV;             // basis points, e.g. 8000 = 80%
        uint256  liquidationThreshold; // basis points, e.g. 8500 = 85%
        uint256  liquidationBonus;   // basis points, e.g. 500 = 5% bonus for liquidator
        uint8    tokenDecimals;
    }

    address[] public collateralList;
    mapping(address => CollateralConfig) public collaterals;

    event CollateralAdded(address indexed token, uint256 maxLTV, uint256 liqThreshold, uint256 liqBonus);
    event CollateralUpdated(address indexed token, uint256 maxLTV, uint256 liqThreshold, uint256 liqBonus);
    event CollateralDisabled(address indexed token);

    constructor(address owner_) Ownable(owner_) {}

    /// @notice Add a new collateral type
    function addCollateral(
        address token,
        uint256 maxLTV,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint8   tokenDecimals
    ) external onlyOwner {
        require(!collaterals[token].enabled, "already added");
        require(maxLTV < liquidationThreshold, "LTV must be < liq threshold");
        require(liquidationThreshold <= BASIS_POINTS, "liq threshold > 100%");
        require(liquidationBonus <= 2000, "bonus too high");

        collaterals[token] = CollateralConfig({
            enabled: true,
            maxLTV: maxLTV,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            tokenDecimals: tokenDecimals
        });
        collateralList.push(token);
        emit CollateralAdded(token, maxLTV, liquidationThreshold, liquidationBonus);
    }

    /// @notice Update risk params for existing collateral
    function updateCollateral(
        address token,
        uint256 maxLTV,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external onlyOwner {
        require(collaterals[token].enabled, "not whitelisted");
        require(maxLTV < liquidationThreshold, "LTV must be < liq threshold");
        collaterals[token].maxLTV = maxLTV;
        collaterals[token].liquidationThreshold = liquidationThreshold;
        collaterals[token].liquidationBonus = liquidationBonus;
        emit CollateralUpdated(token, maxLTV, liquidationThreshold, liquidationBonus);
    }

    /// @notice Disable a collateral (existing positions unaffected)
    function disableCollateral(address token) external onlyOwner {
        collaterals[token].enabled = false;
        emit CollateralDisabled(token);
    }

    function isEnabled(address token) external view returns (bool) {
        return collaterals[token].enabled;
    }

    function getConfig(address token) external view returns (CollateralConfig memory) {
        return collaterals[token];
    }

    function getCollateralList() external view returns (address[] memory) {
        return collateralList;
    }
}
