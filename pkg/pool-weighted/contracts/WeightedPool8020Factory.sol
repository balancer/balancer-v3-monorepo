// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice Weighted Pool factory for 80/20 pools.
 */
contract WeightedPool8020Factory is BasePoolFactory {
    uint256 private constant _EIGHTY = 8e17; // 80%
    uint256 private constant _TWENTY = 2e17; // 20%

    /// @dev By definition, this factory can only create two-token pools.
    error NotTwoTokens();

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @dev It assumes the 80% weight token is first in the array.
     * @param name Name of the pool
     * @param symbol Symbol of the pool
     * @param tokenConfig The token configuration of the pool: must be two-token
     * @param salt Value passed to create3, used to create the address
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        bytes32 salt
    ) external returns (address pool) {
        if (tokenConfig.length != 2) {
            revert NotTwoTokens();
        }

        uint256[] memory weights = new uint256[](2);
        weights[0] = _EIGHTY;
        weights[1] = _TWENTY;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    numTokens: tokenConfig.length,
                    normalizedWeights: weights
                }),
                getVault()
            ),
            salt
        );

        getVault().registerPool(
            pool,
            tokenConfig,
            getNewPoolPauseWindowEndTime(),
            address(0), // no pause manager
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }),
            LiquidityManagement({ supportsAddLiquidityCustom: false, supportsRemoveLiquidityCustom: false })
        );

        _registerPoolWithFactory(pool);
    }
}
