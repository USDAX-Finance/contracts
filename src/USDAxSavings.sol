// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title USDAxSavings
/// @notice USDAX Savings Rate module.
///         Users deposit USDAX and earn a configurable APY funded by protocol
///         stability fees. Rewards are paid in USDAX from a pre-funded pool.
///
///         Design:
///         - apyBps: annual yield in basis points (e.g. 420 = 4.20%)
///         - rewardPool: USDAX deposited by protocol to pay yield
///         - Rewards accrue linearly per second since last checkpoint
///         - No lock-up: withdraw principal + claim rewards any time
contract USDAxSavings is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant YEAR         = 365 days;

    // ─── State ────────────────────────────────────────────────────────────────
    IERC20 public immutable usdax;

    uint256 public apyBps;         // current APY (basis points, e.g. 420 = 4.20%)
    uint256 public rewardPool;     // USDAX available to pay rewards
    uint256 public totalDeposited; // sum of all principal deposits

    struct Position {
        uint256 principal;   // USDAX deposited
        uint256 checkpoint;  // timestamp of last deposit / claim
        uint256 accrued;     // pending rewards not yet transferred to wallet
    }

    mapping(address => Position) public positions;

    // Enumeration
    address[] private _depositors;
    mapping(address => bool) private _hasPosition;

    // ─── Events ───────────────────────────────────────────────────────────────
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 rewardUsdax);
    event RewardsAdded(address indexed by, uint256 amount);
    event ApyUpdated(uint256 oldBps, uint256 newBps);

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(address _usdax, uint256 _apyBps, address _owner) Ownable(_owner) {
        require(_usdax  != address(0), "zero usdax");
        require(_apyBps <= 5_000,      "APY > 50%"); // sanity cap
        usdax   = IERC20(_usdax);
        apyBps  = _apyBps;
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice USDAX rewards accrued but not yet claimed by `user`.
    function pendingRewards(address user) public view returns (uint256) {
        Position storage p = positions[user];
        if (p.principal == 0) return p.accrued;

        uint256 elapsed = block.timestamp - p.checkpoint;
        uint256 earned  = p.principal * apyBps * elapsed / (BASIS_POINTS * YEAR);
        return p.accrued + earned;
    }

    /// @notice Number of unique depositors.
    function depositorCount() external view returns (uint256) {
        return _depositors.length;
    }

    // ─── User actions ─────────────────────────────────────────────────────────

    /// @notice Deposit USDAX into the savings module.
    /// @param amount Amount of USDAX (18 dec) to deposit.
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "zero amount");

        _settle(msg.sender);

        usdax.safeTransferFrom(msg.sender, address(this), amount);

        positions[msg.sender].principal += amount;
        totalDeposited                  += amount;

        if (!_hasPosition[msg.sender]) {
            _hasPosition[msg.sender] = true;
            _depositors.push(msg.sender);
        }

        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraw principal USDAX (does NOT auto-claim rewards).
    /// @param amount Amount of principal to withdraw.
    function withdraw(uint256 amount) external nonReentrant {
        Position storage p = positions[msg.sender];
        require(amount > 0,              "zero amount");
        require(p.principal >= amount,   "insufficient principal");

        _settle(msg.sender);

        p.principal    -= amount;
        totalDeposited -= amount;

        usdax.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claim all pending USDAX rewards.
    function claimRewards() external nonReentrant {
        _settle(msg.sender);

        uint256 reward = positions[msg.sender].accrued;
        require(reward > 0, "no rewards");
        require(rewardPool >= reward, "reward pool empty");

        positions[msg.sender].accrued = 0;
        rewardPool -= reward;

        usdax.safeTransfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    // ─── Owner actions ────────────────────────────────────────────────────────

    /// @notice Fund the reward pool with USDAX (caller must approve first).
    /// @param amount USDAX to transfer into the reward pool.
    function addRewards(uint256 amount) external {
        require(amount > 0, "zero amount");
        usdax.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool += amount;
        emit RewardsAdded(msg.sender, amount);
    }

    /// @notice Update the savings APY.
    /// @param newApyBps New APY in basis points. Max 5000 (50%).
    function setApy(uint256 newApyBps) external onlyOwner {
        require(newApyBps <= 5_000, "APY > 50%");
        emit ApyUpdated(apyBps, newApyBps);
        apyBps = newApyBps;
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Snapshot accrued rewards into `accrued` and reset checkpoint.
    function _settle(address user) internal {
        Position storage p = positions[user];
        if (p.principal > 0) {
            uint256 elapsed = block.timestamp - p.checkpoint;
            uint256 earned  = p.principal * apyBps * elapsed / (BASIS_POINTS * YEAR);
            p.accrued += earned;
        }
        p.checkpoint = block.timestamp;
    }
}
