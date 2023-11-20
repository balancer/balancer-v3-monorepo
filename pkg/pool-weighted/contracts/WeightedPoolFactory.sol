// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import "./WeightedPool.sol";

/**
 * @notice General Weighted Pool factory
 * @dev This is the most general factory, which allows up to four tokens and arbitrary weights.
 */
contract WeightedPoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    constructor(IVault vault, uint256 initialPauseWindowDuration) BasePoolFactory(vault, initialPauseWindowDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Deploys a new `WeightedPool`.
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        uint256[] memory normalizedWeights,
        bytes32 salt
    ) external returns (address pool) {
        // Passing the salt argument causes the contract to be deployed with create2.
        pool = address(
            new WeightedPool{ salt: salt }(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    tokens: tokens,
                    normalizedWeights: normalizedWeights
                }),
                getVault()
            )
        );

        getVault().registerPool(
            pool,
            tokens,
            rateProviders,
            getNewPoolPauseWindowEndTime(),
            address(0), // no pause manager
            PoolCallbacks({
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallAfterSwap: false
            }),
            LiquidityManagement({
                supportsAddLiquidityProportional: true,
                supportsAddLiquiditySingleTokenExactOut: true,
                supportsAddLiquidityUnbalanced: true,
                supportsAddLiquidityCustom: false,
                supportsRemoveLiquidityProportional: true,
                supportsRemoveLiquiditySingleTokenExactIn: true,
                supportsRemoveLiquiditySingleTokenExactOut: true,
                supportsRemoveLiquidityCustom: false
            })
        );

        _registerPoolWithFactory(pool);
    }
}
