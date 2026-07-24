// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {USDAxToken} from "./USDAxToken.sol";
import {CollateralManager} from "./CollateralManager.sol";
import {MockPriceOracle} from "./MockPriceOracle.sol";

/// @title VaultEngine
/// @notice Core CDP engine for USDAX protocol.
///         Users deposit collateral, mint USDAX, repay debt, and withdraw.
///         Undercollateralized positions can be liquidated by anyone.
contract VaultEngine is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────
    uint256 public constant BASIS_POINTS  = 10_000;
    uint256 public constant WAD           = 1e18;
    uint256 public constant MINT_FEE_BPS  = 50;   // 0.5% minting fee
    uint256 public constant MIN_DEBT      = 10e18; // min 10 USDAX to open

    // ─── Dependencies ─────────────────────────────────────────────────────────
    USDAxToken         public immutable usdax;
    CollateralManager  public immutable collateralManager;
    MockPriceOracle    public immutable oracle;

    address public feeRecipient;

    // ─── State ────────────────────────────────────────────────────────────────
    // owner => token => amount
    mapping(address => mapping(address => uint256)) public collateralDeposits;
    // owner => USDAX debt
    mapping(address => uint256) public debt;

    // Track all unique vault owners (for enumeration)
    address[] private _vaultOwners;
    mapping(address => bool) private _hasVault;

    // ─── Events ───────────────────────────────────────────────────────────────
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
    event USDAxMinted(address indexed user, uint256 amount, uint256 fee);
    event USDAxRepaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed vaultOwner,
        address indexed collateralToken,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event FeeRecipientUpdated(address indexed newRecipient);

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(
        address usdax_,
        address collateralManager_,
        address oracle_,
        address feeRecipient_,
        address owner_
    ) Ownable(owner_) {
        usdax             = USDAxToken(usdax_);
        collateralManager = CollateralManager(collateralManager_);
        oracle            = MockPriceOracle(oracle_);
        feeRecipient      = feeRecipient_;
    }

    // ─── User Actions ─────────────────────────────────────────────────────────

    /// @notice Deposit whitelisted collateral into your vault
    function depositCollateral(address token, uint256 amount) external nonReentrant {
        require(collateralManager.isEnabled(token), "token not whitelisted");
        require(amount > 0, "amount zero");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        collateralDeposits[msg.sender][token] += amount;

        _registerOwner(msg.sender);
        emit CollateralDeposited(msg.sender, token, amount);
    }

    /// @notice Mint USDAX against deposited collateral
    /// @param amount Amount of USDAX to mint (before fee)
    function mintUsdax(uint256 amount) external nonReentrant {
        require(amount >= MIN_DEBT, "below min debt");

        uint256 fee = (amount * MINT_FEE_BPS) / BASIS_POINTS;
        uint256 newDebt = debt[msg.sender] + amount;
        debt[msg.sender] = newDebt;

        // Check: new debt must not exceed maxLTV-adjusted collateral value
        require(_maxMintable(msg.sender) >= newDebt, "exceeds max LTV");

        // Mint: user gets amount, fee goes to feeRecipient
        usdax.mint(msg.sender, amount - fee);
        if (fee > 0) usdax.mint(feeRecipient, fee);

        emit USDAxMinted(msg.sender, amount, fee);
    }

    /// @notice Repay USDAX debt
    function repayUsdax(uint256 amount) external nonReentrant {
        require(amount > 0, "amount zero");
        uint256 currentDebt = debt[msg.sender];
        require(currentDebt > 0, "no debt");

        uint256 repay = amount > currentDebt ? currentDebt : amount;
        debt[msg.sender] = currentDebt - repay;
        usdax.burn(msg.sender, repay);

        emit USDAxRepaid(msg.sender, repay);
    }

    /// @notice Withdraw collateral (only if HF stays safe after withdrawal)
    function withdrawCollateral(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "amount zero");
        require(collateralDeposits[msg.sender][token] >= amount, "insufficient collateral");

        collateralDeposits[msg.sender][token] -= amount;

        // If user has debt, check HF stays safely above liquidation boundary after withdrawal.
        // We require HF >= 1.05 (5% buffer) so a small price tick can't immediately liquidate.
        if (debt[msg.sender] > 0) {
            require(_healthFactor(msg.sender) >= (WAD * 105) / 100, "would be near liquidation");
        }

        IERC20(token).safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    // ─── Liquidation ──────────────────────────────────────────────────────────

    /// @notice Liquidate an undercollateralized vault.
    ///         Liquidator repays `debtToRepay` USDAX and receives collateral + bonus.
    /// @param vaultOwner  Address of the vault to liquidate
    /// @param debtToRepay Amount of USDAX the liquidator repays (≤ full debt)
    /// @param collToken   Which collateral token to seize
    function liquidate(
        address vaultOwner,
        uint256 debtToRepay,
        address collToken
    ) external nonReentrant {
        require(vaultOwner != msg.sender, "cannot self-liquidate");
        require(debt[vaultOwner] > 0, "no debt");
        require(_healthFactor(vaultOwner) < WAD, "vault is healthy");

        uint256 userDebt = debt[vaultOwner];
        require(debtToRepay > 0 && debtToRepay <= userDebt, "invalid debtToRepay");

        CollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(collToken);
        require(cfg.enabled, "collateral not whitelisted");

        // How much collateral (in token units) equals debtToRepay USD?
        (uint256 tokenPrice,) = oracle.getPrice(collToken);
        // tokenPrice is 18 decimals, debtToRepay is 18 decimals (USDAX = $1)
        // collateralAmount = debtToRepay / tokenPrice * 10^tokenDecimals
        uint256 collAmount = (debtToRepay * (10 ** cfg.tokenDecimals)) / tokenPrice;

        // Apply liquidation bonus
        uint256 collWithBonus = collAmount + (collAmount * cfg.liquidationBonus / BASIS_POINTS);

        // Cap at vault's available collateral of this token.
        // If collateral (including bonus) exceeds available, scale down debtToRepay
        // proportionally so the liquidator always gets the full bonus on what they repay.
        uint256 available = collateralDeposits[vaultOwner][collToken];
        if (collWithBonus > available) {
            // Recalculate: how much debt can be covered by the available collateral?
            // available = collAmount * (BASIS_POINTS + liquidationBonus) / BASIS_POINTS
            // collAmount = debtToRepay * 10^decimals / tokenPrice
            // Solving for debtToRepay given available:
            //   debtToRepay = available * tokenPrice / 10^decimals
            //                 * BASIS_POINTS / (BASIS_POINTS + liquidationBonus)
            uint256 maxDebt = (available * tokenPrice) / (10 ** cfg.tokenDecimals);
            maxDebt = (maxDebt * BASIS_POINTS) / (BASIS_POINTS + cfg.liquidationBonus);
            require(maxDebt > 0, "vault fully drained");
            debtToRepay  = maxDebt;
            collAmount   = (debtToRepay * (10 ** cfg.tokenDecimals)) / tokenPrice;
            collWithBonus = collAmount + (collAmount * cfg.liquidationBonus / BASIS_POINTS);
            // Final safety clamp (rounding)
            if (collWithBonus > available) collWithBonus = available;
        }

        // Update state
        debt[vaultOwner] -= debtToRepay;
        collateralDeposits[vaultOwner][collToken] -= collWithBonus;

        // Burn liquidator's USDAX and send them the collateral
        usdax.burn(msg.sender, debtToRepay);
        IERC20(collToken).safeTransfer(msg.sender, collWithBonus);

        emit Liquidated(msg.sender, vaultOwner, collToken, debtToRepay, collWithBonus);
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    /// @notice Health factor: WAD = 1.0. Below WAD = liquidatable.
    function healthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /// @notice Total collateral value in USD (18 decimals), adjusted by liqThreshold
    function adjustedCollateralValue(address user) external view returns (uint256) {
        return _adjustedCollateralValue(user);
    }

    /// @notice Raw (unadjusted) collateral value in USD (18 decimals)
    function rawCollateralValue(address user) external view returns (uint256) {
        return _rawCollateralValue(user);
    }

    /// @notice Max USDAX mintable given current collateral (before fee)
    function maxMintable(address user) external view returns (uint256) {
        return _maxMintable(user);
    }

    /// @notice Get all vault owners (for off-chain indexing)
    function getVaultOwners() external view returns (address[] memory) {
        return _vaultOwners;
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "zero address");
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _healthFactor(address user) internal view returns (uint256) {
        uint256 userDebt = debt[user];
        if (userDebt == 0) return type(uint256).max;
        uint256 adjValue = _adjustedCollateralValue(user);
        return (adjValue * WAD) / userDebt;
    }

    /// @dev Collateral value weighted by each token's liquidationThreshold
    function _adjustedCollateralValue(address user) internal view returns (uint256 total) {
        address[] memory tokens = collateralManager.getCollateralList();
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = collateralDeposits[user][token];
            if (amount == 0) continue;

            CollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(token);
            (uint256 price,) = oracle.getPrice(token);

            // USD value: amount (tokenDecimals) * price (18 dec) / 10^tokenDecimals → 18 dec
            uint256 usdValue = (amount * price) / (10 ** cfg.tokenDecimals);
            // Apply liqThreshold
            total += (usdValue * cfg.liquidationThreshold) / BASIS_POINTS;
        }
    }

    /// @dev Collateral value weighted by each token's maxLTV (for mint check)
    function _maxMintable(address user) internal view returns (uint256 total) {
        address[] memory tokens = collateralManager.getCollateralList();
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = collateralDeposits[user][token];
            if (amount == 0) continue;

            CollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(token);
            (uint256 price,) = oracle.getPrice(token);

            uint256 usdValue = (amount * price) / (10 ** cfg.tokenDecimals);
            total += (usdValue * cfg.maxLTV) / BASIS_POINTS;
        }
    }

    /// @dev Raw USD value with no threshold adjustment
    function _rawCollateralValue(address user) internal view returns (uint256 total) {
        address[] memory tokens = collateralManager.getCollateralList();
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = collateralDeposits[user][token];
            if (amount == 0) continue;

            CollateralManager.CollateralConfig memory cfg = collateralManager.getConfig(token);
            (uint256 price,) = oracle.getPrice(token);

            total += (amount * price) / (10 ** cfg.tokenDecimals);
        }
    }

    function _registerOwner(address user) internal {
        if (!_hasVault[user]) {
            _hasVault[user] = true;
            _vaultOwners.push(user);
        }
    }
}
