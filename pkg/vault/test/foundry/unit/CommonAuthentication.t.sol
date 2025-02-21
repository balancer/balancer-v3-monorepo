// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";
import { CommonAuthenticationMock } from "../../../contracts/test/CommonAuthenticationMock.sol";

contract CommonAuthenticationTest is BaseVaultTest {
    CommonAuthenticationMock private commonAuth;
    bytes32 private actionId;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        commonAuth = new CommonAuthenticationMock(vault, bytes32(uint256(uint160(address(this)))));
    }

    function testEnsureAuthenticatedByExclusiveRoleNoAuthNoManager() public {
        address where = address(1234);

        vm.expectCall(
            address(vault.getAuthorizer()),
            abi.encodeCall(
                IAuthorizer.canPerform,
                (
                    commonAuth.getActionId(CommonAuthenticationMock.ensureAuthenticatedByExclusiveRole.selector),
                    address(this),
                    where
                )
            )
        );
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        commonAuth.ensureAuthenticatedByExclusiveRole(where, address(0));
    }

    function testEnsureAuthenticatedByExclusiveRoleWithAuthNoManager() public {
        address where = address(1234);

        // Pass when sender is authorized by governance and there's no manager.
        authorizer.grantRole(
            IAuthentication(address(commonAuth)).getActionId(
                CommonAuthenticationMock.ensureAuthenticatedByExclusiveRole.selector
            ),
            admin
        );

        vm.expectCall(
            address(vault.getAuthorizer()),
            abi.encodeCall(
                IAuthorizer.canPerform,
                (
                    commonAuth.getActionId(CommonAuthenticationMock.ensureAuthenticatedByExclusiveRole.selector),
                    admin,
                    where
                )
            )
        );
        vm.prank(admin);
        commonAuth.ensureAuthenticatedByExclusiveRole(where, address(0));
    }

    function testEnsureAuthenticatedByExclusiveRoleWithAuthWithManager() public {
        address where = address(1234);

        authorizer.grantRole(
            IAuthentication(address(commonAuth)).getActionId(
                CommonAuthenticationMock.ensureAuthenticatedByExclusiveRole.selector
            ),
            admin
        );

        // Revert when authorized but there is another manager.
        vm.prank(admin);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        commonAuth.ensureAuthenticatedByExclusiveRole(where, address(this));
    }

    function testEnsureAuthenticatedByExclusiveRoleWithManager() public view {
        address where = address(1234);

        // Allow when sender is the manager, even without gov permission.
        commonAuth.ensureAuthenticatedByExclusiveRole(where, address(this));
    }

    function testEnsureAuthenticatedByRoleNoAuthNoManager() public {
        address where = address(1234);

        vm.expectCall(
            address(vault.getAuthorizer()),
            abi.encodeCall(
                IAuthorizer.canPerform,
                (
                    commonAuth.getActionId(CommonAuthenticationMock.ensureAuthenticatedByRole.selector),
                    address(this),
                    where
                )
            )
        );
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        commonAuth.ensureAuthenticatedByRole(where, address(0));
    }

    function testEnsureAuthenticatedByRoleWithAuthNoManager() public {
        address where = address(1234);

        // Pass when sender is authorized by governance and there's no manager.
        authorizer.grantRole(
            IAuthentication(address(commonAuth)).getActionId(
                CommonAuthenticationMock.ensureAuthenticatedByRole.selector
            ),
            admin
        );

        vm.expectCall(
            address(vault.getAuthorizer()),
            abi.encodeCall(
                IAuthorizer.canPerform,
                (commonAuth.getActionId(CommonAuthenticationMock.ensureAuthenticatedByRole.selector), admin, where)
            )
        );
        vm.prank(admin);
        commonAuth.ensureAuthenticatedByRole(where, address(0));
    }

    function testEnsureAuthenticatedByRoleWithAuthWithManager() public {
        address where = address(1234);

        authorizer.grantRole(
            IAuthentication(address(commonAuth)).getActionId(
                CommonAuthenticationMock.ensureAuthenticatedByRole.selector
            ),
            admin
        );

        vm.expectCall(
            address(vault.getAuthorizer()),
            abi.encodeCall(
                IAuthorizer.canPerform,
                (commonAuth.getActionId(CommonAuthenticationMock.ensureAuthenticatedByRole.selector), admin, where)
            )
        );
        // Role not exclusive, so this is fine.
        vm.prank(admin);
        commonAuth.ensureAuthenticatedByRole(where, address(this));
    }

    function testEnsureAuthenticatedByRoleWithManager() public view {
        address where = address(1234);

        // Allow when sender is the manager, even without gov permission.
        commonAuth.ensureAuthenticatedByRole(where, address(this));
    }
}
