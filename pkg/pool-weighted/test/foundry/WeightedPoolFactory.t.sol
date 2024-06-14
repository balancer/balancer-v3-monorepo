// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";

contract WeightedPoolFactoryTest is Test {
    VaultMock vault;
    WeightedPoolFactory factory;

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function testFactoryPausedState() public {
        uint32 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }
}
