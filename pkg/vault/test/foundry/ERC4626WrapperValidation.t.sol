// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { Vault } from "vault/contracts/Vault.sol";
import { VaultMockDeployer } from "vault/test/foundry/utils/VaultMockDeployer.sol";
import { VaultMock } from "vault/contracts/test/VaultMock.sol";
import { ERC4626BufferPoolFactory } from "vault/contracts/factories/ERC4626BufferPoolFactory.sol";
import { ERC4626BufferPool } from "vault/contracts/ERC4626BufferPool.sol";
import { ERC4626TokenMock } from "./utils/ERC4626TokenMock.sol";
import { ERC4626TokenBrokenRateMock } from "./utils/ERC4626TokenBrokenRateMock.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract ERC4626WrapperValidation is BaseVaultTest {
    ERC4626BufferPoolFactory factory;

    IERC4626 wBrokenDAI;
    IERC4626 wBrokenUSDC;

    IERC4626 wDAI;
    IERC4626 wUSDC;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        factory = new ERC4626BufferPoolFactory(IVault(address(vault)), 365 days);

        // Tokens with non-linear rate calculations
        wBrokenDAI = new ERC4626TokenBrokenRateMock("wBrokenDAI", "wBrokenDAI", 1e27, 1e27, dai);
        wBrokenUSDC = new ERC4626TokenBrokenRateMock("wBrokenUSDC", "wBrokenUSDC", 1e15, 1e15, usdc);

        // Tokens with linear rate calculations
        wDAI = new ERC4626TokenMock("wDAI", "wDAI", 1e27, 1e27, dai);
        wUSDC = new ERC4626TokenMock("wUSDC", "wUSDC", 1e15, 1e15, usdc);
    }

    function testFactoryWithInvalidWrapper() public {
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626BufferPoolFactory.IncompatibleWrappedToken.selector, address(wBrokenDAI))
        );
        // wBrokenDAI has a wrong rate, so it should revert
        factory.ensureValidWrappedToken(wBrokenDAI);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626BufferPoolFactory.IncompatibleWrappedToken.selector, address(wBrokenUSDC))
        );
        // wBrokenUSDC has a wrong rate, so it should revert
        factory.ensureValidWrappedToken(wBrokenUSDC);
    }

    function testFactoryWithValidWrappers() public view {
        // These tokens with linear rate should not revert
        factory.ensureValidWrappedToken(wDAI);
        factory.ensureValidWrappedToken(wUSDC);
    }
}
