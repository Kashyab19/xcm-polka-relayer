// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Import Remix’s test library
import "remix_tests.sol";
import "../contracts/MockERC20.sol";
import "../contracts/CollateralVault.sol";

contract CollateralVaultTest {
    MockERC20        token;
    CollateralVault  vault;
    address          user;

    uint256 initialBalance;

    /// Runs before any test
    function beforeAll() public {
        user = address(this);
        // 1. Deploy a mock token and vault
        token = new MockERC20("Test Token", "TKN");
        vault = new CollateralVault();
        // 2. Ensure this test contract has tokens
        initialBalance = token.balanceOf(user);
        Assert.isTrue(initialBalance > 0, "Should mint tokens to test contract");
    }

    /// Test that depositERC20 stores collateral correctly
    function testDepositERC20() public {
        uint256 depositAmount = 100 * 10**18;
        // 1. Approve the vault
        token.approve(address(vault), depositAmount);
        // 2. Deposit
        vault.depositERC20(address(token), depositAmount);
        // 3. Check stored deposit
        uint256 stored = vault.erc20Deposits(user, address(token));
        Assert.equal(stored, depositAmount, "Stored deposit should match depositAmount");
    }

    /// Test that requestXcmLock reduces the stored deposit and emits the event
    function testRequestXcmLock() public {
        uint256 before = vault.erc20Deposits(user, address(token));
        uint256 lockAmount =  50 * 10**18;
        // 1. Call the XCM stub
        vault.requestXcmLock(address(token), lockAmount, bytes32("KUSAMA"));
        // 2. Verify store updated
        uint256 after1 = vault.erc20Deposits(user, address(token));
        Assert.equal(after1, before - lockAmount, "Deposit should decrease by lockAmount");
        // 3. The CrossChainCollateralLockRequested event will appear in the Remix test logs
    }
}
