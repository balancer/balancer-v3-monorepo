// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626BufferPool } from "../ERC4626BufferPool.sol";
import { BasePoolFactory } from "./BasePoolFactory.sol";

/**
 * @notice Factory for ERC4626 Buffer Pools
 * @dev These are internal pools used with "Boosted Pools" to provide a reservoir of base tokens to support swaps.
 * Ideally we would deploy a pool on buffer creation, but this would require including the pool bytecode in the
 * Vault (or extension), which of course would not fit.
 */
contract ERC4626BufferPoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(ERC4626BufferPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @param wrappedToken The ERC4626 wrapped token associated with the buffer and pool
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(IERC4626 wrappedToken, bytes32 salt) external authenticate returns (address pool) {
        pool = _create(
            abi.encode(
                string.concat("Balancer Buffer-", wrappedToken.name()),
                string.concat("BB-", wrappedToken.symbol()),
                wrappedToken,
                getVault()
            ),
            salt
        );

        getVault().registerBuffer(wrappedToken, pool, getNewPoolPauseWindowEndTime());

        _registerPoolWithFactory(pool);
    }
}
