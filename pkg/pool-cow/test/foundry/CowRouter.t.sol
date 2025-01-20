// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { CowRouter } from "../../contracts/CowRouter.sol";

contract CowRouterTest is BaseVaultTest {
    CowRouter private _cowRouter;

    function setUp() public override {
        super.setUp();

        authorizer.grantRole(vault.getActionId(ICowRouter.setProtocolFeePercentage.selector), admin);

        _cowRouter = new CowRouter(vault);
    }

    function testSetProtocolFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _cowRouter.setProtocolFeePercentage(50e16);
    }

    function testSetProtocolFeePercentageCappedAtMax() public {
        // 50% is above the 10% limit.
        uint256 newProtocolFeePercentage = 50e16;
        uint256 protocolFeePercentageLimit = 10e16;

        vm.expectRevert(
            abi.encodeWithSelector(
                ICowRouter.ProtocolFeePercentageAboveLimit.selector,
                newProtocolFeePercentage,
                protocolFeePercentageLimit
            )
        );
        vm.prank(admin);
        _cowRouter.setProtocolFeePercentage(50e16);
    }

    function testSetProtocolFeePercentage() public {
        // 5% protocol fee percentage.
        uint256 newProtocolFeePercentage = 5e16;

        vm.prank(admin);
        _cowRouter.setProtocolFeePercentage(newProtocolFeePercentage);

        assertEq(_cowRouter.getProtocolFeePercentage(), newProtocolFeePercentage, "Protocol Fee Percentage is not set");
    }
}
