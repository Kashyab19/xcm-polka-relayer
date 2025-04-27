// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A 1:1 “swap” mock for fee‐asset → borrow‐asset conversion
contract MockAssetConversion {
    /// @dev Swaps `amountIn` of tokenIn for tokenOut at 1:1, honoring `minAmountOut` stub
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 /* minAmountOut */
    ) external returns (uint256 amountOut) {
        // pull feeAsset
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "transferFrom failed"
        );
        // send back same amount of tokenOut
        require(IERC20(tokenOut).transfer(msg.sender, amountIn),
            "transfer failed"
        );
        return amountIn;
    }
}
