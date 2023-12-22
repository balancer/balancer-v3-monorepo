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
     * @param highWeightTokenType The 80% token's type
     * @param lowWeightTokenType The 20% token's type
     * @param highWeightRateProvider The 80% token's rate provider
     * @param lowWeightRateProvider The 20% token's rate provider
     * @param salt Value passed to create3, used to create the address
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20 highWeightToken,
        IERC20 lowWeightToken,
        IVault.TokenType highWeightTokenType,
        IVault.TokenType lowWeightTokenType,
        IRateProvider highWeightRateProvider,
        IRateProvider lowWeightRateProvider,
        bytes32 salt
    ) external returns (address pool) {
        IVault.TokenConfig[] memory tokens = new IVault.TokenConfig[](2);
        tokens[0].token = highWeightToken;
        tokens[0].tokenType = highWeightTokenType;
        tokens[0].rateProvider = highWeightRateProvider;
        tokens[1].token = lowWeightToken;
        tokens[1].tokenType = lowWeightTokenType;
        tokens[1].rateProvider = lowWeightRateProvider;

        uint256[] memory weights = new uint256[](2);
        weights[0] = _EIGHTY;
        weights[1] = _TWENTY;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    tokens: _extractTokensFromTokenConfig(tokens),
                    normalizedWeights: weights
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
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }),
            LiquidityManagement({ supportsAddLiquidityCustom: false, supportsRemoveLiquidityCustom: false })
        );

        _registerPoolWithFactory(pool);
    }
}
