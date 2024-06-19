// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract VaultAdminMutationTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testGetPoolTokenRatesWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.getPoolTokenRates(address(0));
    }

    /*
      getPoolTokenRates
        [x] withRegisteredPool
        [x] onlyVault
    */
    function testGetPoolTokenRatesWhenNotVault() public {
        vm.expectRevert();
        vaultExtension.getPoolTokenRates(pool);
    }

    /*
      isVaultPaused
        [x] onlyVault
    */
    function testIsVaultPausedWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.isVaultPaused();
    }

    /*
      getVaultPausedState
        [x] onlyVault
    */
    function testGetVaultPausedStateWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.getVaultPausedState();
    }

    /*
      pauseVault
        [x] onlyVault
        [x] authenticate
    */
    function testPauseVaultWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.pauseVault();
    }

    function testPauseVaultWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.pauseVault();
    }

    /*
      unpauseVault
        [x] onlyVault
        [x] authenticate
    */
    function testUnpauseVaultWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.unpauseVault();
    }

    function testUnpauseVaultWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.unpauseVault();
    }

    /*
      pausePool
        [x] withRegisteredPool
        [x] onlyVault
        [x] authenticate
    */
    function testPausePoolWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.pausePool(address(0));
    }

    function testPausePoolWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.pausePool(pool);
    }

    function testPausePoolWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.pausePool(pool);
    }

    /*
      unpausePool
        [x] withRegisteredPool
        [x] onlyVault
        [x] authenticate
    */
    function testUnpausePoolWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.pausePool(address(0));
    }

    function testUnpausePoolWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.unpausePool(pool);
    }

    function testUnpausePoolWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.unpausePool(address(0));
    }

    /*
      setStaticSwapFeePercentage
        [x] withRegisteredPool
        [x] onlyVault
        [x] authenticate
    */
    function testSetStaticSwapFeePercentageWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.setStaticSwapFeePercentage(address(0), 1);
    }

    function testSetStaticSwapFeePercentageWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.setStaticSwapFeePercentage(pool, 1);
    }

    function testSetStaticSwapFeePercentageWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.setStaticSwapFeePercentage(pool, 1);
    }

    /*
      collectProtocolFees
        [] nonReentrant
        [x] onlyVault
    */
    function testCollectProtocolFeesWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.collectAggregateFees(pool);
    }

    /*
      enableRecoveryMode
        [x] withRegisteredPool
        [x] onlyVault
    */
    function testEnableRecoveryModeWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.enableRecoveryMode(address(0));
    }

    function testEnableRecoveryModeWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.enableRecoveryMode(pool);
    }

    /*
      disableRecoveryMode
        [x] withRegisteredPool
        [x] authenticate
        [x] onlyVault
    */
    function testDisableRecoveryModeWithoutRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0)));
        vault.disableRecoveryMode(address(0));
    }

    function testDisableRecoveryModeWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.disableRecoveryMode(pool);
    }

    /*
      disableQuery
        [x] authenticate
        [x] onlyVault
    */
    function testDisableQueryWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.disableQuery();
    }

    function testDisableQueryWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.disableQuery();
    }

    /*
      setAuthorizer
        [] nonReentrant
        [x] authenticate
        [x] onlyVault
    */
    function testSetAuthorizerWhenNotAuthenticated() public {
        vm.expectRevert(abi.encodeWithSelector(IAuthentication.SenderNotAllowed.selector));
        vault.setAuthorizer(_authorizer);
    }

    function testSetAuthorizerWhenNotVault() public {
        vm.expectRevert();
        vaultAdmin.setAuthorizer(_authorizer);
    }
}
