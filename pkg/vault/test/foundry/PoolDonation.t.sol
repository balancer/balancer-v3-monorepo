// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolDonationTest is BaseVaultTest {
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();

        PoolConfig memory config = vault.getPoolConfig(pool);
        config.liquidityManagement.enableDonation = true;
        vault.manualSetPoolConfig(pool, config);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testUnbalancedDonationToPool() public {
        uint256 amountToDonate = poolInitAmount / 10;

        uint256[] memory amountsToDonate = new uint256[](2);
        amountsToDonate[daiIdx] = amountToDonate;

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.prank(bob);
        router.donate(pool, amountsToDonate, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        // Bob balances.
        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            amountToDonate,
            "Bob DAI balance is wrong"
        );
        assertEq(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Bob USDC balance is wrong");
        assertEq(balancesAfter.userBpt, balancesBefore.userBpt, "Bob BPT balance is wrong");

        // Pool balances.
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            amountToDonate,
            "Pool DAI balance is wrong"
        );
        assertEq(balancesAfter.poolTokens[usdcIdx], balancesBefore.poolTokens[usdcIdx], "Pool USDC balance is wrong");
        assertEq(balancesAfter.poolSupply, balancesBefore.poolSupply, "Pool BPT supply is wrong");

        // Vault Balances.
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            amountToDonate,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx],
            "Vault USDC balance is wrong"
        );
    }
}
