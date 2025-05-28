// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { FeeBurnerAuthenticationMock } from "../../contracts/test/FeeBurnerAuthenticationMock.sol";

contract FeeBurnerAuthenticationTest is BaseVaultTest {
    address protocolFeeSweeper = makeAddr("ProtocolFeeSweeper");

    FeeBurnerAuthenticationMock feeBurnerAuth;

    function setUp() public virtual override {
        super.setUp();

        feeBurnerAuth = new FeeBurnerAuthenticationMock(vault, IProtocolFeeSweeper(protocolFeeSweeper));

        authorizer.grantRole(
            IAuthentication(address(feeBurnerAuth)).getActionId(
                FeeBurnerAuthenticationMock.manualOnlyFeeRecipientOrGovernance.selector
            ),
            admin
        );
    }

    function testOnlyProtocolFeeSweeper() external {
        vm.prank(protocolFeeSweeper);
        feeBurnerAuth.manualOnlyProtocolFeeSweeper();
    }

    function testOnlyProtocolFeeSweeperRevertIfSenderIsNotSweeper() external {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurnerAuth.manualOnlyProtocolFeeSweeper();
    }

    function testOnlyFeeRecipient() external {
        _mockGetFeeRecipient();

        vm.prank(alice);
        feeBurnerAuth.manualOnlyFeeRecipientOrGovernance();
    }

    function testOnlyGovernance() external {
        _mockGetFeeRecipient();

        vm.prank(admin);
        feeBurnerAuth.manualOnlyFeeRecipientOrGovernance();
    }

    function testOnlyFeeRecipientOrGovernanceRevertIfSenderIsWrong() external {
        _mockGetFeeRecipient();

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeBurnerAuth.manualOnlyFeeRecipientOrGovernance();
    }

    function _mockGetFeeRecipient() internal {
        vm.mockCall(
            protocolFeeSweeper,
            abi.encodeWithSelector(IProtocolFeeSweeper.getFeeRecipient.selector),
            abi.encode(alice)
        );
    }
}
