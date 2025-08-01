// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseERC4626BufferTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseERC4626BufferTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { TokenPairRegistry } from "../../contracts/TokenPairRegistry.sol";

contract TokenPairRegistryTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;

    TokenPairRegistry internal registry;

    function setUp() public virtual override {
        super.setUp();
        registry = new TokenPairRegistry(vault, admin);
    }

    function testAddPathPermissioned() external {
        address tokenIn = address(waDAI);
        IBatchRouter.SwapPathStep[] memory steps;

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        registry.addPath(tokenIn, steps);
    }
}
