// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal ERC20-only vault + XCM-lock stub
contract CollateralVault {
    // user → token → deposited amount
    mapping(address => mapping(address => uint256)) public erc20Deposits;

    event ERC20Deposited(
        address indexed user,
        address indexed token,
        uint256         amount
    );

    event CrossChainCollateralLockRequested(
        address indexed user,
        address         token,
        uint256         amount,
        bytes32         destChain
    );

    /// @notice Deposit ERC20 collateral
    function depositERC20(address token, uint256 amount) external {
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "ERC20 transfer failed"
        );
        erc20Deposits[msg.sender][token] += amount;
        emit ERC20Deposited(msg.sender, token, amount);
    }

    /// @notice Stub: lock collateral on another chain via XCM
    function requestXcmLock(
        address token,
        uint256 amount,
        bytes32 destChain
    ) external {
        uint256 bal = erc20Deposits[msg.sender][token];
        require(bal >= amount, "Insufficient collateral");
        erc20Deposits[msg.sender][token] = bal - amount;
        emit CrossChainCollateralLockRequested(
          msg.sender, token, amount, destChain
        );
    }
}
