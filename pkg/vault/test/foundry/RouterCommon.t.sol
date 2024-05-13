// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ReentrancyAttack } from "@balancer-labs/v3-solidity-utils/contracts/test/ReentrancyAttack.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { RouterCommonMock } from "../../contracts/test/RouterCommonMock.sol";

contract RouterCommonTest is BaseTest {
    ReentrancyAttack reentrancyAttack;
    RouterCommonMock router;

    function setUp() public virtual override {
        BaseTest.setUp();

        router = new RouterCommonMock(IVault(address(0x01)), weth, IPermit2(address(0x02)));
        reentrancyAttack = new ReentrancyAttack();
    }

    function testCallAndSaveSender() external {
        vm.expectEmit();
        emit RouterCommonMock.CurrentSenderMock(address(this));

        router.callAndSaveSender(
            abi.encodeWithSelector(
                RouterCommon.callAndSaveSender.selector,
                abi.encodeWithSelector(RouterCommonMock.emitSender.selector)
            )
        );
    }

    function testCallAndSaveSenderWithReentrancyAttack() external {
        vm.expectEmit();
        emit RouterCommonMock.CurrentSenderMock(address(this));

        router.callAndSaveSender(
            abi.encodeWithSelector(
                RouterCommonMock.call.selector,
                reentrancyAttack,
                abi.encodeWithSelector(
                    ReentrancyAttack.callSender.selector,
                    abi.encodeWithSelector(
                        RouterCommon.callAndSaveSender.selector,
                        abi.encodeWithSelector(RouterCommonMock.emitSender.selector)
                    )
                )
            )
        );
    }
}
