// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626BufferPoolFactory } from "@balancer-labs/v3-vault/contracts/factories/ERC4626BufferPoolFactory.sol";

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
    function createMocked(IERC4626 wrappedToken) external returns (address pool) {
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

        // Token order is wrapped first, then base.
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0].token = IERC20(wrappedToken);
        tokenConfig[0].tokenType = TokenType.ERC4626;
        // We are assuming the baseToken is STANDARD (the default type, with enum value 0).
        tokenConfig[1].token = IERC20(wrappedToken.asset());

        getVault().registerPool(
            pool,
            tokenConfig,
            getNewPoolPauseWindowEndTime(),
            address(0),
            PoolHooks({
                shouldCallBeforeInitialize: true, // ensure proportional
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: true, // ensure custom
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: true, // ensure proportional
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: true, // rebalancing
                shouldCallAfterSwap: false
            }),
            LiquidityManagement({ supportsAddLiquidityCustom: true, supportsRemoveLiquidityCustom: false })
        );
    }
}
