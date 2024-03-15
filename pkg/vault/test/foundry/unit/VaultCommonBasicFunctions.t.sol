// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonBasicFunctionsTest is BaseVaultTest {
    // The pauseWindowEndTime is stored as a 32 bits number
    uint256 private constant _MAX_PAUSE_END_TIME = 2 ** 32 - 1;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                  _getPoolTokenInfo
    *******************************************************************************/

    // _poolTokenConfig[pool] is empty
    // _poolTokenBalances[pool] is empty
    // _poolConfig[pool] is empty
    // All configurations are correct (Maybe fuzz for balances)

    /*******************************************************************************
                                _ensurePoolNotPaused
    *******************************************************************************/

    function testPausedPoolWithBigEndTime() public {
        vault.manualSetPoolPaused(address(pool), true, _MAX_PAUSE_END_TIME);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, address(pool)));
        vault.testEnsurePoolNotPaused(address(pool));
    }

    function testVaultAndPoolUnpaused() public {
        vault.manualSetVaultState(false, true, 3e16, 5e17);
        vault.manualSetPoolPaused(address(pool), false, 1);
        VaultState memory vaultState = vault.testEnsureUnpausedAndGetVaultState(address(pool));
        assertEq(vaultState.isVaultPaused, false);
        assertEq(vaultState.isQueryDisabled, true);
        assertEq(vaultState.protocolSwapFeePercentage, 3e16);
        assertEq(vaultState.protocolYieldFeePercentage, 5e17);
    }
}
