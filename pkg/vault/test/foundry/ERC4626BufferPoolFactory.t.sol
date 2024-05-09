// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC4626BufferPoolFactory } from "vault/contracts/factories/ERC4626BufferPoolFactory.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ERC4626BufferPoolFactoryTest is BaseVaultTest {
    ERC4626BufferPoolFactory internal factory;

    function setUp() public override {
        BaseVaultTest.setUp();
        factory = new ERC4626BufferPoolFactory(IVault(address(vault)), 365 days);
    }

    function testFactoryPausedState() public {
        uint256 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }
}
