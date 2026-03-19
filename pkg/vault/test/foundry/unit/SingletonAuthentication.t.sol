// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import "../../../contracts/test/SingletonAuthenticationMock.sol";
import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import "../../../contracts/CommonAuthentication.sol";

contract SingletonAuthenticationTest is BaseVaultTest {
    SingletonAuthenticationMock internal auth;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        auth = new SingletonAuthenticationMock(vault);
    }

    function testGetVault() public view {
        assertEq(address(auth.getVault()), address(vault), "Wrong vault address");
    }

    function testGetAuthorizer() public view {
        assertEq(address(auth.getAuthorizer()), address(vault.getAuthorizer()), "Wrong authorizer address");
    }

    function testNoVault() public {
        vm.expectRevert(CommonAuthentication.VaultNotSet.selector);
        new SingletonAuthenticationMock(IVault(address(0)));
    }

    function testSwapModifier() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        auth.swapModifier(pool);
    }
}
