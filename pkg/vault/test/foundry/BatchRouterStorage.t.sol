// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import {
    TransientEnumerableSet
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/TransientEnumerableSet.sol";

import {
    TransientStorageHelpers,
    AddressMappingSlot
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterStorageTest is BaseVaultTest {
    string private constant DOMAIN = "BatchRouterStorage";

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testCurrentSwapTokensInSlot() external view {
        assertEq(
            batchRouter.manualGetCurrentSwapTokensInSlot(),
            TransientStorageHelpers.calculateSlot(DOMAIN, "currentSwapTokensIn")
        );
    }

    function testCurrentSwapTokensOutSlot() external view {
        assertEq(
            batchRouter.manualGetCurrentSwapTokensOutSlot(),
            TransientStorageHelpers.calculateSlot(DOMAIN, "currentSwapTokensOut")
        );
    }

    function testCurrentSwapTokenInAmountsSlot() external view {
        assertEq(
            AddressMappingSlot.unwrap(batchRouter.manualGetCurrentSwapTokenInAmounts()),
            TransientStorageHelpers.calculateSlot(DOMAIN, "currentSwapTokenInAmounts")
        );
    }

    function testCurrentSwapTokenOutAmountsSlot() external view {
        assertEq(
            AddressMappingSlot.unwrap(batchRouter.manualGetCurrentSwapTokenOutAmounts()),
            TransientStorageHelpers.calculateSlot(DOMAIN, "currentSwapTokenOutAmounts")
        );
    }

    function testSettledTokenAmountsSlot() external view {
        assertEq(
            AddressMappingSlot.unwrap(batchRouter.manualGetSettledTokenAmounts()),
            TransientStorageHelpers.calculateSlot(DOMAIN, "settledTokenAmounts")
        );
    }
}
