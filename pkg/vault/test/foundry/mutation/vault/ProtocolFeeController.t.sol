// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ProtocolFeeController } from "@balancer-labs/v3-vault/contracts/ProtocolFeeController.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract ProtocolFeeControllerMutationTest is BaseVaultTest {
    function testCollectAggregateFeesHookWhenNotVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        ProtocolFeeController((address(feeController))).collectAggregateFeesHook(address(0), IERC20(address(0)));
    }
}
