// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockPriceOracle} from "../src/MockPriceOracle.sol";
import {USDAxToken} from "../src/USDAxToken.sol";
import {CollateralManager} from "../src/CollateralManager.sol";
import {VaultEngine} from "../src/VaultEngine.sol";

contract Deploy is Script {
    // ── Risk params (basis points) ──────────────────────────────────────────
    uint256 constant WETH_LTV   = 8000; // 80%
    uint256 constant WETH_LIQ   = 8500; // 85%
    uint256 constant WETH_BONUS = 500;  // 5%

    uint256 constant WBTC_LTV   = 7500;
    uint256 constant WBTC_LIQ   = 8000;
    uint256 constant WBTC_BONUS = 500;

    uint256 constant STETH_LTV   = 7500;
    uint256 constant STETH_LIQ   = 8000;
    uint256 constant STETH_BONUS = 500;

    // ── Initial prices (USD, 18 decimals) ───────────────────────────────────
    uint256 constant WETH_PRICE  = 2000e18;
    uint256 constant WBTC_PRICE  = 65000e18;
    uint256 constant STETH_PRICE = 1980e18;

    function run() external {
        address deployer = msg.sender;

        console.log("Deployer:", deployer);
        console.log("Balance: ", deployer.balance / 1e18, "ETH");

        vm.startBroadcast();

        // 1. Mock collateral tokens
        MockERC20 weth  = new MockERC20("Wrapped Ether",          "WETH",  18, deployer);
        MockERC20 wbtc  = new MockERC20("Wrapped Bitcoin",        "WBTC",   8, deployer);
        MockERC20 steth = new MockERC20("Staked Ether",           "stETH", 18, deployer);

        console.log("WETH  :", address(weth));
        console.log("WBTC  :", address(wbtc));
        console.log("stETH :", address(steth));

        // 2. Price oracle
        MockPriceOracle oracle = new MockPriceOracle(deployer);

        address[] memory tokens = new address[](3);
        uint256[] memory prices = new uint256[](3);
        tokens[0] = address(weth);  prices[0] = WETH_PRICE;
        tokens[1] = address(wbtc);  prices[1] = WBTC_PRICE;
        tokens[2] = address(steth); prices[2] = STETH_PRICE;
        oracle.setPrices(tokens, prices);

        console.log("Oracle:", address(oracle));

        // 3. CollateralManager
        CollateralManager cm = new CollateralManager(deployer);
        cm.addCollateral(address(weth),  WETH_LTV,  WETH_LIQ,  WETH_BONUS,  18);
        cm.addCollateral(address(wbtc),  WBTC_LTV,  WBTC_LIQ,  WBTC_BONUS,   8);
        cm.addCollateral(address(steth), STETH_LTV, STETH_LIQ, STETH_BONUS, 18);

        console.log("CollateralManager:", address(cm));

        // 4. USDAxToken
        USDAxToken usdax = new USDAxToken(deployer);

        console.log("USDAxToken:", address(usdax));

        // 5. VaultEngine
        VaultEngine vault = new VaultEngine(
            address(usdax),
            address(cm),
            address(oracle),
            deployer,   // feeRecipient = deployer for now
            deployer
        );

        console.log("VaultEngine:", address(vault));

        // 6. Wire: set VaultEngine as minter in USDAxToken
        usdax.setVaultEngine(address(vault));

        vm.stopBroadcast();

        // ── Summary ──────────────────────────────────────────────────────────
        console.log("\n======== DEPLOYMENT COMPLETE ========");
        console.log("Network    : Robinhood Chain Testnet (46630)");
        console.log("Deployer   :", deployer);
        console.log("-------------------------------------");
        console.log("WETH       :", address(weth));
        console.log("WBTC       :", address(wbtc));
        console.log("stETH      :", address(steth));
        console.log("Oracle     :", address(oracle));
        console.log("CollMgr    :", address(cm));
        console.log("USDAxToken :", address(usdax));
        console.log("VaultEngine:", address(vault));
        console.log("=====================================");
    }
}
