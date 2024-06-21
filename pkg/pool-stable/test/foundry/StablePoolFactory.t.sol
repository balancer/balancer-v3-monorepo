// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

contract StablePoolFactoryTest is Test {
    VaultMock vault;
    StablePoolFactory factory;

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }
}
//
