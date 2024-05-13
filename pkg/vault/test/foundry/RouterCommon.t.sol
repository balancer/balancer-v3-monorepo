// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { RouterCommon } from "../../contracts/RouterCommon.sol";

contract RouterCommonTest is BaseTest {
    RouterCommon router;

    function setUp() public virtual override {
        BaseTest.setUp();

        router = new RouterCommon(IVault(address(0x01)), weth, IPermit2(address(0x02)));
    }

    function testCallAndSaveSender() external {
        bytes memory result = router.callAndSaveSender(abi.encodeWithSelector(RouterCommon.getSender.selector));
        assertEq(abi.decode(result, (address)), address(this));
    }
}
