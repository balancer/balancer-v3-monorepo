// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

// SystemRoleUpgradeable is an abstract base contract of the EURe token
interface ISystemRoleUpgradeable {
    function addSystemAccount(address account) external;
    function addAdminAccount(address account) external;
}

// Mint functions are on the token contract
interface IEUReV2 is ISystemRoleUpgradeable {
    function mint(address to, uint256 amount) external;
    function setMintAllowance(address account, uint256 amount) external;
}

/**
 * @notice Demo for addressing the disparity between reserves and balances of the migrated EURe token.
 * @dev V1 appears to have access control issues (owner doesn't have the required PREDICATE role).
 */
contract FixEUReV2 is Test {
    address constant VAULT = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;

    // Address of the migrated EURe token. Old V1 address was 0xcB444e90D8198415266c6a2724b7900fb12FC56E
    address constant EURE_V2 = 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430;

    // Multisig owner of both V1 and V2
    address constant OWNER = 0x8001EA269cb9715Bf7acFf89c664ffC134A519ec;
    
    IVault vault = IVault(VAULT);
    
    function setUp() public {
        // This issue is on the Gnosis chain
        vm.createSelectFork("https://rpc.gnosischain.com");
    }
    
    function test_V2SettleFailsBeforeFix() public {
        vm.expectRevert();
        vault.unlock(abi.encodeCall(this.settleCallback, IERC20(EURE_V2)));
    }
    
    function test_FixV2() public {   
        uint256 reserves = vault.getReservesOf(IERC20(EURE_V2));
        uint256 balance = IERC20(EURE_V2).balanceOf(VAULT);
        uint256 deficit = reserves - balance;
        
        // Must be admin to add system account
        vm.startPrank(OWNER);
        ISystemRoleUpgradeable(EURE_V2).addAdminAccount(OWNER);
        ISystemRoleUpgradeable(EURE_V2).addSystemAccount(address(this));
        vm.stopPrank();
        
        // Must set the mint allowance before minting (needs admin permission)
        vm.prank(OWNER);
        IEUReV2(EURE_V2).setMintAllowance(address(this), deficit);

        // Mint to the Vault (needs system permission)
        IEUReV2(EURE_V2).mint(VAULT, deficit);
        
        // Now call settle after adjusting the Vault's token balance
        vault.unlock(abi.encodeCall(this.settleCallback, IERC20(EURE_V2)));
        
        // Verify that the reserves have been updated
        uint256 newReserves = vault.getReservesOf(IERC20(EURE_V2));
        uint256 newBalance = IERC20(EURE_V2).balanceOf(VAULT);
        
        assertEq(newReserves, newBalance, "Reserves should match balance");
    }
    
    function settleCallback(IERC20 token) external returns (bytes memory) {
        vault.settle(token, 0);

        return bytes("");
    }
}
