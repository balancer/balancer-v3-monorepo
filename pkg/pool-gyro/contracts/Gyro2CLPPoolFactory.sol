// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IGyro2CLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";

import { Gyro2CLPPool } from "./Gyro2CLPPool.sol";

/**
 * @notice Gyro 2-CLP Pool factory.
 * @dev This is the pool factory for 2-CLP Gyro pools, which supports two tokens only.
 */
contract Gyro2CLPPoolFactory is IPoolVersion, BasePoolFactory, Version {
    // solhint-disable not-rely-on-time

    /// @notice 2-CLP pools support 2 tokens only.
    error SupportsOnlyTwoTokens();

    string private _poolVersion;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, pauseWindowDuration, type(Gyro2CLPPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Deploys a new `Gyro2CLPPool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param sqrtAlpha square root of first element in price range
     * @param sqrtBeta square root of last element in price range
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param poolHooksContract Contract that implements the hooks for the pool
     * @param enableDonation If true, the pool will support the donation add liquidity mechanism
     * @param disableUnbalancedLiquidity If true, only proportional add and remove liquidity are accepted
     * @param salt The salt value that will be passed to create2 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        uint256 sqrtAlpha,
        uint256 sqrtBeta,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        address poolHooksContract,
        bool enableDonation,
        bool disableUnbalancedLiquidity,
        bytes32 salt
    ) external returns (address pool) {
        if (tokens.length != 2) {
            revert SupportsOnlyTwoTokens();
        }

        if (roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        pool = _create(
            abi.encode(
                IGyro2CLPPool.GyroParams({
                    name: name,
                    symbol: symbol,
                    sqrtAlpha: sqrtAlpha,
                    sqrtBeta: sqrtBeta,
                    version: _poolVersion
                }),
                getVault()
            ),
            salt
        );

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.enableDonation = enableDonation;
        // disableUnbalancedLiquidity must be set to true if a hook has the flag enableHookAdjustedAmounts = true.
        liquidityManagement.disableUnbalancedLiquidity = disableUnbalancedLiquidity;

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
