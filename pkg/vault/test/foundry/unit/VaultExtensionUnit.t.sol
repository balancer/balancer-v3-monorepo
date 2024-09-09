// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import { PoolHooksMock } from "../../../contracts/test/PoolHooksMock.sol";

contract VaultExtensionUnitTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testItWorks() public pure {
        assertTrue(true);
    }

    function testComputeDynamicSwapFeePercentageRevert() public {
        PoolSwapParams memory params;
        HooksConfig memory hooksConfig = vault.getHooksConfig(pool);
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        // should fail
        PoolHooksMock(poolHooksContract).setFailOnComputeDynamicSwapFeeHook(true);
        vm.expectRevert(IVaultErrors.DynamicSwapFeeHookFailed.selector);
        vault.computeDynamicSwapFeePercentage(pool, params);
    }
}
