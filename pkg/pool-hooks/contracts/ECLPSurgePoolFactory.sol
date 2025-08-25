// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { GyroECLPPool } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPool.sol";

/// @notice ECLP Pool factory that deploys a standard ECLPPool with a ECLPSurgeHook.
contract ECLPSurgePoolFactory is IPoolVersion, BasePoolFactory, Version {
    address private immutable _eclpSurgeHook;

    string private _poolVersion;

    uint256 private constant _NUM_TOKENS = 2;

    constructor(
        address eclpSurgeHook,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    )
        BasePoolFactory(
            SingletonAuthentication(eclpSurgeHook).getVault(),
            pauseWindowDuration,
            type(GyroECLPPool).creationCode
        )
        Version(factoryVersion)
    {
        _eclpSurgeHook = eclpSurgeHook;
        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Getter for the internally deployed ECLP surge hook contract.
     * @dev This hook will be registered to every pool created by this factory.
     * @return eclpSurgeHook Address of the deployed ECLPSurgeHook
     */
    function getECLPSurgeHook() external view returns (address) {
        return _eclpSurgeHook;
    }

    /**
     * @notice Deploys a new `StablePool`.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokens An array of descriptors for the tokens the pool will manage
     * @param eclpParams parameters to configure the pool
     * @param derivedEclpParams parameters with 38 decimals precision, to configure the pool
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     * @param enableDonation If true, the pool will support the donation add liquidity mechanism
     * @param disableUnbalancedLiquidity If true, only proportional add and remove liquidity are accepted
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokens,
        IGyroECLPPool.EclpParams memory eclpParams,
        IGyroECLPPool.DerivedEclpParams memory derivedEclpParams,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage,
        bool enableDonation,
        bool disableUnbalancedLiquidity,
        bytes32 salt
    ) external returns (address pool) {
        if (roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        // As the ECLP Pool deployment does not know about the tokens, and the registration doesn't know about the
        // pool type, we enforce the token limit at the factory level.
        if (tokens.length > _NUM_TOKENS) {
            revert IVaultErrors.MaxTokens();
        }

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.enableDonation = enableDonation;
        liquidityManagement.disableUnbalancedLiquidity = disableUnbalancedLiquidity;

        pool = _create(
            abi.encode(
                IGyroECLPPool.GyroECLPPoolParams({
                    name: name,
                    symbol: symbol,
                    eclpParams: eclpParams,
                    derivedEclpParams: derivedEclpParams,
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
            address(_eclpSurgeHook),
            liquidityManagement
        );
    }
}
