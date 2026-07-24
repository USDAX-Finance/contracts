// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {USDAxToken} from "../src/USDAxToken.sol";
import {VaultEngine} from "../src/VaultEngine.sol";
import {USDAxSavings} from "../src/USDAxSavings.sol";

/// @dev Deploys USDAxSavings for the v1.1.0 contract set on Robinhood Chain Testnet.
///      Seeds the reward pool with USDAX obtained by minting against WETH collateral.
///
///      Run:
///        forge script script/DeploySavings.s.sol \
///          --rpc-url https://rpc.testnet.chain.robinhood.com/rpc \
///          --broadcast --legacy --skip-simulation \
///          --private-key $DEPLOYER_PRIVATE_KEY -vvvv
contract DeploySavings is Script {
    // v1.1.0 deployed addresses (Robinhood Chain Testnet 46630)
    address constant WETH         = 0x728a06069E7A7DBafe2a92bc1E3e4d48e8fC49Dc;
    address constant USDAX        = 0x89F2c042def8719930904A474FF999A0F8fddd64;
    address constant VAULT_ENGINE = 0xB5d971d69728B0C31b19A8f184d31813F29EEA20;

    // Savings params
    uint256 constant APY_BPS      = 420;      // 4.20% APY
    uint256 constant WETH_AMOUNT  = 1e18;     // 1 WETH collateral (worth ~$3500)
    uint256 constant USDAX_MINT   = 1_000e18; // Mint 1000 USDAX (well within 80% LTV on $3500 WETH)
    uint256 constant REWARD_SEED  = 900e18;   // Seed 900 USDAX into reward pool (90%)

    function run() external {
        address deployer = msg.sender;
        console.log("Deployer  :", deployer);
        console.log("Balance   :", deployer.balance / 1e18, "ETH");

        vm.startBroadcast();

        // 1. Deploy USDAxSavings with 4.20% APY
        USDAxSavings savings = new USDAxSavings(USDAX, APY_BPS, deployer);
        console.log("USDAxSavings:", address(savings));

        // 2. Claim testnet WETH via faucet
        MockERC20(WETH).faucet();
        console.log("Claimed testnet WETH from faucet");

        // 3. Approve VaultEngine to spend WETH
        IERC20(WETH).approve(VAULT_ENGINE, WETH_AMOUNT);

        // 4. Deposit WETH as collateral
        VaultEngine(VAULT_ENGINE).depositCollateral(WETH, WETH_AMOUNT);
        console.log("Deposited 1 WETH into VaultEngine");

        // 5. Mint 1000 USDAX (0.5% fee => 5 USDAX fee, 995 USDAX received)
        VaultEngine(VAULT_ENGINE).mintUsdax(USDAX_MINT);
        console.log("Minted 1000 USDAX (995 received after 0.5% fee)");

        // 6. Approve savings contract to pull USDAX for reward pool
        IERC20(USDAX).approve(address(savings), REWARD_SEED);

        // 7. Seed the reward pool
        savings.addRewards(REWARD_SEED);
        console.log("Seeded reward pool with 900 USDAX");

        vm.stopBroadcast();

        console.log("\n======== SAVINGS DEPLOYMENT COMPLETE ========");
        console.log("Network      : Robinhood Chain Testnet (46630)");
        console.log("USDAxSavings :", address(savings));
        console.log("APY          : 4.20%  (420 bps)");
        console.log("Reward Pool  : 900 USDAX");
        console.log("=============================================");
        console.log("Next: set CONTRACT_SAVINGS=<address> in your environment");
    }
}
