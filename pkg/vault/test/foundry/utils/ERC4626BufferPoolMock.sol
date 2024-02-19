// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { ERC4626BufferPool } from "@balancer-labs/v3-vault/contracts/ERC4626BufferPool.sol";
import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

contract ERC4626BufferPoolMock is ERC4626BufferPool {
    constructor(
        string memory name,
        string memory symbol,
        IERC4626 wrappedToken,
        IVault vault
    ) ERC4626BufferPool(name, symbol, wrappedToken, vault) {}

    /// @inheritdoc BasePoolHooks
    function onBeforeInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) external view override onlyVault returns (bool) {
        // Does not enforce proportionality, so we can create unbalanced buffer pools on tests
        return exactAmountsInScaled18.length == 2;
    }
}