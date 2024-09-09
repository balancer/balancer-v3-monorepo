// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice General Weighted Pool factory
 * @dev This is the most general factory, which allows up to eight tokens and arbitrary weights.
 */
contract WeightedPoolFactory is IPoolVersion, BasePoolFactory, Version {
    // solhint-disable not-rely-on-time

    string private _poolVersion;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param poolHooksContract Contract that implements the hooks for the pool
     * @param enableDonation If true, the pool will support the donation add liquidity mechanism
     * @param disableAddLiquidityUnbalanced If true, liquidity can only be added proportionally
     * @param disableRemoveLiquidityUnbalanced If true, liquidity can only be removed proportionally
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256[] memory normalizedWeights,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        address poolHooksContract,
        bool enableDonation,
        bool disableAddLiquidityUnbalanced,
        bool disableRemoveLiquidityUnbalanced,
        bytes32 salt
    ) external returns (address pool) {
        if (roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.enableDonation = enableDonation;

        // disableAddLiquidityUnbalanced must be true if a hook set the flag enableHookAdjustedAmountsOnAdd.
        // disableRemoveLiquidityUnbalanced must be true if a hook set the flag enableHookAdjustedAmountsOnRemove.
        liquidityManagement.disableAddLiquidityUnbalanced = disableAddLiquidityUnbalanced;
        liquidityManagement.disableRemoveLiquidityUnbalanced = disableRemoveLiquidityUnbalanced;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    numTokens: tokens.length,
                    normalizedWeights: normalizedWeights,
                    version: _poolVersion
                }),
                getVault()
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokens,
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }
}
