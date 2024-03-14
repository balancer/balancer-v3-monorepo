// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";

import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice Weighted Pool factory for 80/20 pools.
 */
contract WeightedPool8020Factory is BasePoolFactory {
    uint256 private constant _EIGHTY = 8e17; // 80%
    uint256 private constant _TWENTY = 2e17; // 20%
    mapping(IERC20 => mapping(IERC20 => address)) private _poolAddresses;

    /// @dev The pool containing the combination of tokens and weights has already been created.
    error PoolAlreadyExists();

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
     * @param lowWeightTokenConfig The token configuration of the low weight token
     * @param salt Value passed to create3, used to create the address
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig memory highWeightTokenConfig,
        TokenConfig memory lowWeightTokenConfig,
        bytes32 salt
    ) external returns (address pool) {
        IERC20 highWeightToken = highWeightTokenConfig.token;
        IERC20 lowWeightToken = lowWeightTokenConfig.token;

        // Tokens must be sorted.
        uint256 highWeightTokenIdx = highWeightToken > lowWeightToken ? 1 : 0;
        uint256 lowWeightTokenIdx = highWeightTokenIdx == 0 ? 1 : 0;

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        uint256[] memory weights = new uint256[](2);

        weights[highWeightTokenIdx] = _EIGHTY;
        weights[lowWeightTokenIdx] = _TWENTY;

        tokenConfig[highWeightTokenIdx] = highWeightTokenConfig;
        tokenConfig[lowWeightTokenIdx] = lowWeightTokenConfig;

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

        if (_poolAddresses[highWeightToken][lowWeightToken] != address(0)) {
            revert PoolAlreadyExists();
        }

        _poolAddresses[highWeightToken][lowWeightToken] = pool;

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

    /**
     * @notice Gets the address of the pool with the respective tokens and weights.
     * @param highWeightToken The token with 80% weight in the pool.
     * @param lowWeightToken The token with 20% weight in the pool.
     */
    function getPool(IERC20 highWeightToken, IERC20 lowWeightToken) external view returns (address pool) {
        pool = _poolAddresses[highWeightToken][lowWeightToken];
    }
}
