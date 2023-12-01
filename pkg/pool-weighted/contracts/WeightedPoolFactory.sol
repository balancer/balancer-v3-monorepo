// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolCallbacks, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice General Weighted Pool factory
 * @dev This is the most general factory, which allows up to four tokens and arbitrary weights.
 */
contract WeightedPoolFactory is BasePoolFactory {
    // solhint-disable not-rely-on-time

    // We set the `crossChainDeploymentProtection` flag to true in the base contract, ensuring unique pool addresses
    // across chains.
    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, true, type(WeightedPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens The tokens that will be registered to the pool
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory normalizedWeights,
        bytes32 salt
    ) external returns (address pool) {
        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    tokens: tokens,
                    normalizedWeights: normalizedWeights
                }),
                getVault()
            ),
            salt
        );

        getVault().registerPool(
            pool,
            tokens,
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
