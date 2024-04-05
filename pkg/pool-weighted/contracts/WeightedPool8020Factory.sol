// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @dev Since tokens must be sorted, pass in explicit 80/20 token config structs.
     * @param highWeightTokenConfig The token configuration of the high weight token
     * @param lowWeightTokenConfig The token configuration of the low weight token
     * @param swapFeePercentage Initial swap fee percentage
     */
    function create(
        TokenConfig memory highWeightTokenConfig,
        TokenConfig memory lowWeightTokenConfig,
        uint256 swapFeePercentage
    ) external returns (address pool) {
        IERC20 highWeightToken = highWeightTokenConfig.token;
        IERC20 lowWeightToken = lowWeightTokenConfig.token;

        // Tokens must be sorted.
        (uint256 highWeightTokenIdx, uint256 lowWeightTokenIdx) = highWeightToken > lowWeightToken ? (1, 0) : (0, 1);

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        uint256[] memory weights = new uint256[](2);

        weights[highWeightTokenIdx] = _EIGHTY;
        weights[lowWeightTokenIdx] = _TWENTY;

        tokenConfig[highWeightTokenIdx] = highWeightTokenConfig;
        tokenConfig[lowWeightTokenIdx] = lowWeightTokenConfig;

        bytes32 salt = _calculateSalt(highWeightToken, lowWeightToken);

        string memory highWeightTokenSymbol = IERC20Metadata(address(highWeightToken)).symbol();
        string memory lowWeightTokenSymbol = IERC20Metadata(address(lowWeightToken)).symbol();

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: string.concat("Balancer 80 ", highWeightTokenSymbol, " 20 ", lowWeightTokenSymbol),
                    symbol: string.concat("B-80", highWeightTokenSymbol, "-20", lowWeightTokenSymbol),
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
            swapFeePercentage,
            getNewPoolPauseWindowEndTime(),
            address(0), // no pause manager,
            address(0), // no pool creator
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
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false
            }),
            false // hasDynamicSwapFee
        );

        _registerPoolWithFactory(pool);
    }

    /**
     * @notice Gets the address of the pool with the respective tokens and weights.
     * @param highWeightToken The token with 80% weight in the pool.
     * @param lowWeightToken The token with 20% weight in the pool.
     */
    function getPool(IERC20 highWeightToken, IERC20 lowWeightToken) external view returns (address pool) {
        bytes32 salt = _calculateSalt(highWeightToken, lowWeightToken);
        pool = getDeploymentAddress(salt);
    }

    function _calculateSalt(IERC20 highWeightToken, IERC20 lowWeightToken) internal view returns (bytes32 salt) {
        salt = keccak256(abi.encode(block.chainid, highWeightToken, lowWeightToken));
    }
}
