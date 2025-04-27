// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// Minimal ERC-20 interface
interface IERC20 {
    function transferFrom(address from, address to, uint256 amt) external returns (bool);
    function transfer(address to, uint256 amt) external returns (bool);
    function approve(address spender, uint256 amt) external returns (bool);
}

/// Vault interface for checking collateral
interface IVault {
    function erc20Deposits(address user, address token) external view returns (uint256);
}

/// Mock swap interface
interface IAssetConversion {
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 /*minOut*/
    ) external returns (uint256);
}

/// @notice Borrow up to 50% LTV, pay 0.5% fee in any asset via on-chain swap
contract LendingEngine {
    address public vault;
    IAssetConversion public conv;
    IERC20 public collateralToken;
    IERC20 public borrowAsset;

    uint256 constant LTV_BPS   = 5_000; // 50%
    uint256 constant FEE_BPS   =    50; // 0.5%
    uint256 constant BPS_DENOM = 10_000;

    mapping(address => uint256) public borrows;

    constructor(
        address _vault,
        address _conv,
        address _collateral,
        address _borrow
    ) {
        vault          = _vault;
        conv           = IAssetConversion(_conv);
        collateralToken= IERC20(_collateral);
        borrowAsset    = IERC20(_borrow);
    }

    /// @notice Pulls feeAsset, swaps fee→borrowAsset, then sends `amount`
    function borrow(
        uint256 amount,
        address feeAsset,
        uint256 /*minOut*/
    ) external {
        // 1) LTV check
        uint256 col = IVault(vault).erc20Deposits(msg.sender, address(collateralToken));
        require(borrows[msg.sender] + amount <= (col * LTV_BPS) / BPS_DENOM);

        // 2) fee pull & swap
        uint256 feeAmt = (amount * FEE_BPS) / BPS_DENOM;
        IERC20(feeAsset).transferFrom(msg.sender, address(this), feeAmt);
        IERC20(feeAsset).approve(address(conv), feeAmt);
        conv.swapExactInput(feeAsset, address(borrowAsset), feeAmt, 0);

        // 3) record & send borrow
        borrows[msg.sender] += amount;
        borrowAsset.transfer(msg.sender, amount);
    }

    /// @notice Simple repay
    function repay(uint256 amount) external {
        borrows[msg.sender] -= amount;
        borrowAsset.transferFrom(msg.sender, address(this), amount);
    }
}
