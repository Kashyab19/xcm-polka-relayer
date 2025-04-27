// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal hackathon‐style lending pool
/// @dev Single‐collateral, fixed 50% collateral factor, no interest accrual
contract LendingPool {
    IERC20 public immutable collateral;
    IERC20 public immutable borrowAsset;
    uint256 public constant COLLATERAL_FACTOR = 50; // 50%

    // user → deposited collateral amount
    mapping(address => uint256) public deposits;
    // user → borrowed amount
    mapping(address => uint256) public borrows;

    /// @param _collateral   ERC20 used as collateral
    /// @param _borrowAsset  ERC20 users can borrow
    constructor(IERC20 _collateral, IERC20 _borrowAsset) {
        collateral  = _collateral;
        borrowAsset = _borrowAsset;
    }

    /// @notice Deposit collateral into the pool
    function deposit(uint256 amount) external {
        deposits[msg.sender] += amount;
        require(
            collateral.transferFrom(msg.sender, address(this), amount),
            "Collateral transfer failed"
        );
    }

    /// @notice Borrow up to COLLATERAL_FACTOR% of your deposited value
    function borrow(uint256 amount) external {
        uint256 maxBorrow = (deposits[msg.sender] * COLLATERAL_FACTOR) / 100;
        require(
            borrows[msg.sender] + amount <= maxBorrow,
            "Exceeds collateral factor"
        );
        borrows[msg.sender] += amount;
        require(
            borrowAsset.transfer(msg.sender, amount),
            "Borrow transfer failed"
        );
    }

    /// @notice Repay borrowed tokens
    function repay(uint256 amount) external {
        require(
            borrows[msg.sender] >= amount,
            "Repay exceeds borrowed amount"
        );
        borrows[msg.sender] -= amount;
        require(
            borrowAsset.transferFrom(msg.sender, address(this), amount),
            "Repay transfer failed"
        );
    }

    /// @notice Withdraw your collateral (only if fully repaid)
    function withdraw(uint256 amount) external {
        require(
            borrows[msg.sender] == 0,
            "Outstanding borrow exists"
        );
        require(
            deposits[msg.sender] >= amount,
            "Withdraw exceeds deposit"
        );
        deposits[msg.sender] -= amount;
        require(
            collateral.transfer(msg.sender, amount),
            "Withdraw transfer failed"
        );
    }

    // ─── Hackathon XCM Stub ──────────────────────────────────────────────────────

    /// @notice Emitted when a cross-chain borrow is requested
    event CrossBorrowRequested(
        address indexed user,
        uint256         amount,
        bytes32         destParaId
    );

    /// @notice Stub function for off-chain relayer to capture and later XCM
    function crossBorrow(
        uint256 amount,
        bytes32 destParaId
    )
        external
    {
        emit CrossBorrowRequested(msg.sender, amount, destParaId);
    }
    // ────────────────────────────────────────────────────────────────────────────
}
