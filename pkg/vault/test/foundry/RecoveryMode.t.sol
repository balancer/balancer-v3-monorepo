// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract RecoveryModeTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testRecoveryModeBalances() public {
        // Add initial liquidity
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, defaultAmount, false, bytes(""));

        // Raw and live should be in sync
        assertRawAndLiveBalanceRelationship(true);

        // Put pool in recovery mode
        vault.manualEnableRecoveryMode(address(pool));

        // Approve router to burn BPT
        vm.prank(alice);
        BalancerPoolToken(pool).approve(address(router), bptAmountOut / 2);

        // Do a recovery withdrawal
        vm.prank(alice);
        router.removeLiquidityRecovery(address(pool), bptAmountOut / 2);

        // Raw and live should be out of sync
        assertRawAndLiveBalanceRelationship(false);

        vault.manualDisableRecoveryMode(address(pool));

        // Raw and live should be back in sync
        assertRawAndLiveBalanceRelationship(true);
    }

    function assertRawAndLiveBalanceRelationship(bool shouldBeEqual) internal {
        // Ensure raw and last live balances are in sync after the operation
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastLiveBalances = vault.getLastLiveBalances(pool);

        assertEq(currentLiveBalances.length, lastLiveBalances.length);

        for (uint256 i = 0; i < currentLiveBalances.length; i++) {
            bool areEqual = currentLiveBalances[i] == lastLiveBalances[i];

            shouldBeEqual ? assertTrue(areEqual) : assertFalse(areEqual);
        }
    }
}
