// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract VaultExtensionMutationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*
        isUnlocked
            [x] onlyVault
    */
    function testIsUnlockedWhenNotVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NotVaultDelegateCall.selector));
        vaultExtension.isUnlocked();
    }

    /*
        getNonzeroDeltaCount
            [x] onlyVault
    */
    function testGetNonzeroDeltaCountWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getTokenDelta(dai);
    }

    /*
        getTokenDelta
            [x] onlyVault
    */
    function testGetTokenDeltaWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getTokenDelta(dai);
    }

    /*
        getReservesOf
            [x] onlyVault
    */
    function testGetReservesOfWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getReservesOf(dai);
    }

    /*
        isPoolRegistered
            [x] onlyVault
    */
    function testIsPoolRegisteredWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.isPoolRegistered(pool);
    }

    /*
        isPoolInitialized
            [x] onlyVault
    */
    function testIsPoolInitializedWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.isPoolInitialized(pool);
    }

    /*
        getPoolConfig
            [x] onlyVault
    */
    function testGetPoolConfigWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getPoolConfig(pool);
    }

    /*
        getPoolTokens
            [x] onlyVault
    */
    function testGetPoolTokensWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getPoolTokens(pool);
    }

    /*
        getPoolTokenInfo
            [x] onlyVault
    */
    function testGetPoolTokenInfoWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getPoolTokenInfo(pool);
    }

    /*
        totalSupply
            [x] onlyVault
    */
    function testTotalSupplyWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.totalSupply(address(dai));
    }

    /*
        balanceOf
            [x] onlyVault
    */
    function testBalanceOfWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.balanceOf(address(dai), address(0));
    }

    /*
        allowance
            [x] onlyVault
    */
    function testAllowanceWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.allowance(address(dai), address(1), address(2));
    }

    /*
        transfer
            [x] onlyVault
    */
    function testTransferWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.transfer(address(0), address(1), 1);
    }

    /*
        approve
            [x] onlyVault
    */
    function testApproveWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.approve(address(0), address(1), 0);
    }

    /*
        transferFrom
            [x] onlyVault
    */
    function testTransferFromWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.transferFrom(address(0), address(1), address(2), 2);
    }

    /*
        isPoolPaused
            [x] onlyVault
    */
    function testIsPoolPausedWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.isPoolPaused(pool);
    }

    /*
        getPoolPausedState
            [x] onlyVault
    */
    function testGetPoolPausedStateWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getPoolPausedState(pool);
    }

    /*
        getStaticSwapFeePercentage
            [x] onlyVault
    */
    function testGetStaticSwapFeePercentageWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getStaticSwapFeePercentage(pool);
    }

    /*
        getStaticSwapFeeManager
            [x] onlyVault
    */
    function testGetStaticSwapFeeManagerWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getPoolRoleAccounts(pool);
    }

    /*
        isPoolInRecoveryMode
            [x] onlyVault
    */
    function testIsPoolInRecoveryModeWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.isPoolInRecoveryMode(pool);
    }

    /*
        quote
            [x] onlyVault
    */
    function testQuoteWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.quote(bytes(""));
    }

    /*
        isQueryDisabled
            [x] onlyVault
    */
    function testIsQueryDisabledWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.isQueryDisabled();
    }
}
