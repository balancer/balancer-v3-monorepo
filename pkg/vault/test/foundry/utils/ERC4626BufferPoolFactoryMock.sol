// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626BufferPoolFactory } from "../../../contracts/factories/ERC4626BufferPoolFactory.sol";
import { ERC4626BufferPoolMock } from "./ERC4626BufferPoolMock.sol";

/// @notice Factory for Mock ERC4626 Buffer Pools
contract ERC4626BufferPoolFactoryMock is ERC4626BufferPoolFactory {
    constructor(IVault vault, uint256 pauseWindowDuration) ERC4626BufferPoolFactory(vault, pauseWindowDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `ERC4626BufferPoolMock`.
     * @dev Buffers might need an external pause manager (e.g., a large depositor). This is permissionless,
     * so anyone can create a buffer for any wrapper. As a safety measure, we validate the wrapper for
     * ERC4626-compatibility.
     *
     * @param wrappedToken The ERC4626 wrapped token associated with the buffer and pool
     */
    function createMocked(IERC4626 wrappedToken, IRateProvider rateProvider) external returns (address pool) {
        // Ensure the wrappedToken is compatible with the Vault
        if (_isValidWrappedToken(wrappedToken) == false) {
            revert IncompatibleWrappedToken(address(wrappedToken));
        }

        pool = address(
            new ERC4626BufferPoolMock(
                string.concat("Balancer Buffer-", wrappedToken.name()),
                string.concat("BB-", wrappedToken.symbol()),
                wrappedToken,
                getVault()
            )
        );

        _registerPoolWithFactory(pool);

        _registerPoolWithVault(
            pool,
            wrappedToken,
            rateProvider,
            getNewPoolPauseWindowEndTime(),
            address(0),
            address(0),
            _getDefaultPoolHooks(),
            _getDefaultLiquidityManagement()
        );
    }
}
