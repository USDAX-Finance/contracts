// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockPriceOracle
/// @notice Testnet price oracle — owner sets USD prices manually
/// @dev Prices use 18 decimals. e.g. ETH=$2000 → 2000e18
contract MockPriceOracle is Ownable {
    struct PriceData {
        uint256 price;     // USD price, 18 decimals
        uint256 updatedAt; // block.timestamp of last update
    }

    mapping(address => PriceData) private _prices;

    event PriceSet(address indexed token, uint256 price, uint256 timestamp);

    constructor(address owner_) Ownable(owner_) {}

    /// @notice Set price for a token (owner only)
    function setPrice(address token, uint256 usdPrice18) external onlyOwner {
        _prices[token] = PriceData({price: usdPrice18, updatedAt: block.timestamp});
        emit PriceSet(token, usdPrice18, block.timestamp);
    }

    /// @notice Batch set prices
    function setPrices(address[] calldata tokens, uint256[] calldata prices) external onlyOwner {
        require(tokens.length == prices.length, "length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            _prices[tokens[i]] = PriceData({price: prices[i], updatedAt: block.timestamp});
            emit PriceSet(tokens[i], prices[i], block.timestamp);
        }
    }

    /// @notice Get USD price for token. Reverts if price not set or stale (>24h)
    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt) {
        PriceData memory d = _prices[token];
        require(d.price > 0, "Oracle: price not set");
        require(block.timestamp - d.updatedAt <= 24 hours, "Oracle: price stale");
        return (d.price, d.updatedAt);
    }

    /// @notice Get price without staleness check (read-only helper)
    function getPriceUnsafe(address token) external view returns (uint256 price, uint256 updatedAt) {
        PriceData memory d = _prices[token];
        return (d.price, d.updatedAt);
    }
}
