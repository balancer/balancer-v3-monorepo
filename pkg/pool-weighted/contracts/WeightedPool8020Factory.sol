// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import "./WeightedPool.sol";

/**
 * @notice Weighted Pool factory for 80/20 pools.
 */
contract WeightedPool8020Factory is BasePoolFactory {
    uint256 private constant _EIGHTY = 8e17; // 80%
    uint256 private constant _TWENTY = 2e17; // 20%

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @param name Name of the pool
     * @param symbol Symbol of the pool
     * @param highWeightToken The 80% token
     * @param lowWeightToken The 20% token
     * @param salt Value passed to create3, used to create the address
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20 highWeightToken,
        IERC20 lowWeightToken,
        IRateProvider highWeightRateProvider,
        IRateProvider lowWeightRateProvider,
        bytes32 salt
    ) external returns (address pool) {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = highWeightToken;
        tokens[1] = lowWeightToken;

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = highWeightRateProvider;
        rateProviders[1] = lowWeightRateProvider;

        uint256[] memory weights = new uint256[](2);
        weights[0] = _EIGHTY;
        weights[1] = _TWENTY;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({ name: name, symbol: symbol, tokens: tokens, normalizedWeights: weights }),
                getVault()
            ),
            salt
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
