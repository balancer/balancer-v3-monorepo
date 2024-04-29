// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasePoolFactory } from "@balancer-labs/v3-vault/contracts/factories/BasePoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseHook } from "./BaseHook.sol";
import { WeightedPoolWithHooks } from "./WeightedPoolWithHooks.sol";

/**
 * @title WeightedPoolWithHookFactory
 * @notice The contract allows deploying a Weighted Pool with an attached hooks contract.
 */
contract WeightedPoolWithHooksFactory is BasePoolFactory {
    error InvalidHooksContract();

    constructor(
        IVault vault,
        uint256 pauseWindowDuration
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPoolWithHooks).creationCode) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Deploys a new `WeightedPoolWithHooks` and `CustomHooks` contracts
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param swapFeePercentage Initial swap fee percentage
     * @param salt The salt value that will be passed to create3 deployment
     * @param pauseManager The address of the pause manager
     * @param hooks The address of the hooks contract
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        bytes32 salt,
        address pauseManager,
        address hooks
    ) external returns (address pool) {
        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    numTokens: tokens.length,
                    normalizedWeights: normalizedWeights
                }),
                getVault(),
                hooks
            ),
            salt
        );

        BaseHook hooksContract = BaseHook(hooks);

        getVault().registerPool(
            pool,
            tokens,
            swapFeePercentage,
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            address(0), // no pool creator
            hooksContract.availableHooks(),
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false
            })
        );

        hooksContract.registerPool(pool);

        _registerPoolWithFactory(pool);
    }
}
