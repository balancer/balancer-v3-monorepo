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

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @dev Since tokens must be sorted, pass in explicit 80/20 token config structs.
     * @param name Name of the pool
     * @param symbol Symbol of the pool
     * @param highWeightTokenConfig The token configuration of the high weight token
     * @param lowWeightTokenConfig The token configuration of the high weight token
     * @param salt Value passed to create3, used to create the address
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig memory highWeightTokenConfig,
        TokenConfig memory lowWeightTokenConfig,
        bytes32 salt
    ) external returns (address pool) {
        // Tokens must be sorted.
        uint256 highWeightTokenIdx = highWeightTokenConfig.token > lowWeightTokenConfig.token ? 1 : 0;
        uint256 lowWeightTokenIdx = highWeightTokenIdx == 0 ? 1 : 0;

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        uint256[] memory weights = new uint256[](2);
        IERC20[] memory tokens = new IERC20[](2);

        weights[highWeightTokenIdx] = _EIGHTY;
        weights[lowWeightTokenIdx] = _TWENTY;

        tokenConfig[highWeightTokenIdx] = highWeightTokenConfig;
        tokenConfig[lowWeightTokenIdx] = lowWeightTokenConfig;

        tokens[highWeightTokenIdx] = highWeightTokenConfig.token;
        tokens[lowWeightTokenIdx] = lowWeightTokenConfig.token;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({ name: name, symbol: symbol, tokens: tokens, normalizedWeights: weights }),
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
